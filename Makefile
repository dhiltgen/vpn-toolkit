ARCH_OS := $(shell docker info --format='{{.Architecture}}:{{.OperatingSystem}}')

include env

# If the base layer isn't ~close to your host OS, then
# various networking tools might not work properly
# (e.g., alpine images don't seem to work properly on debian)
ifneq (,$(findstring armv7l:Raspbian,$(ARCH_OS)))
    # Raspberry PI
    VPN_BASE=resin/rpi-raspbian
    TAG=armv7l-raspbian
else ifneq (,$(findstring x86_64:Debian,$(ARCH_OS)))
    # Linux x86
    VPN_BASE=debian:8
    TAG=x86_64-debian8
else ifneq (,$(findstring x86_64:Ubuntu 16.04,$(ARCH_OS)))
    # Linux x86
    VPN_BASE=ubuntu:16.04
    TAG=x86_64-ubuntu16.04
else
    # Something else?
    $(error Unsupported OS/architecture $(ARCH_OS))
endif

export VPN_BASE
export TAG
# In VPN configs "left" == "local" and "right" == "remote"
export LEFT

COMMON_DISTRIB_FILES= \
    ca.pem \
    docker-compose.yaml \
    Dockerfile.vpn.debian \
    Makefile \
    README.md \


IMAGE = dhiltgen/vpn-toolkit:$(TAG)

build: env
	docker-compose build
	echo "TAG=$(TAG)" > .env

pki: $(NODE1_NAME).pem $(NODE2_NAME).pem

ca.pem:
	docker run -v $(shell pwd):/data -w /data $(IMAGE) \
	    ipsec pki --gen --outform pem > ca-key.pem
	chmod 600 ca-key.pem
	docker run -v $(shell pwd):/data -w /data $(IMAGE) \
	    ipsec pki --self --in ca-key.pem --dn 'C=US, CN=VPN CA' --ca --outform pem > ca.pem

%.pem: ca.pem
	docker run -v $(shell pwd):/data -w /data $(IMAGE) \
	    ipsec pki --gen --outform pem > $*-key.pem
	chmod 600 $*-key.pem
	docker run -v $(shell pwd):/data -w /data $(IMAGE) \
	    sh -c "ipsec pki --pub --in $*-key.pem | ipsec pki --issue --cacert ca.pem --cakey ca-key.pem --dn 'C=US, CN=$*' --outform pem" > $*.pem

push:
	docker-compose push

.node1.sed:
	@echo "s|%%LEFT_NAME%%|$(NODE1_NAME)|g" > $@ ; \
	echo "s|%%LEFT_CIDR%%|$(NODE1_CIDR)|g" >> $@ ; \
	echo "s|%%LEFT_PUB%%|$(NODE1_PUB)|g" >> $@ ; \
	echo "s|%%RIGHT_NAME%%|$(NODE2_NAME)|g" >> $@ ; \
	echo "s|%%RIGHT_CIDR%%|$(NODE2_CIDR)|g" >> $@ ; \
	echo "s|%%RIGHT_PUB%%|$(NODE2_PUB)|g" >> $@

.node2.sed:
	@echo "s|%%LEFT_NAME%%|$(NODE2_NAME)|g" > $@ ; \
	echo "s|%%LEFT_CIDR%%|$(NODE2_CIDR)|g" >> $@ ; \
	echo "s|%%LEFT_PUB%%|$(NODE2_PUB)|g" >> $@ ; \
	echo "s|%%RIGHT_NAME%%|$(NODE1_NAME)|g" >> $@ ; \
	echo "s|%%RIGHT_CIDR%%|$(NODE1_CIDR)|g" >> $@ ; \
	echo "s|%%RIGHT_PUB%%|$(NODE1_PUB)|g" >> $@

distrib: .node1.sed .node2.sed $(NODE1_NAME).pem $(NODE2_NAME).pem
	@mkdir $(NODE1_NAME) && \
	    cp $(COMMON_DISTRIB_FILES) env $(NODE1_NAME)/ && \
	    cp $(NODE1_NAME).pem $(NODE1_NAME)/left.pem && \
	    cp $(NODE1_NAME)-key.pem $(NODE1_NAME)/left-key.pem && \
	    cp $(NODE2_NAME).pem $(NODE1_NAME)/right.pem && \
	    sed -f .node1.sed < ipsec.conf.tmpl > $(NODE1_NAME)/ipsec.conf && \
	    sed -f .node1.sed < ipsec.secrets.tmpl > $(NODE1_NAME)/ipsec.secrets && \
	    echo "LEFT=$(NODE1_NAME)" >> $(NODE1_NAME)/env && \
	    tar zcf  $(NODE1_NAME)-distrib.tgz $(NODE1_NAME) && rm -rf $(NODE1_NAME)
	@mkdir $(NODE2_NAME) && \
	    cp $(COMMON_DISTRIB_FILES) env $(NODE2_NAME)/ && \
	    cp $(NODE2_NAME).pem $(NODE2_NAME)/left.pem && \
	    cp $(NODE2_NAME)-key.pem $(NODE2_NAME)/left-key.pem && \
	    cp $(NODE1_NAME).pem $(NODE2_NAME)/right.pem && \
	    sed -f .node2.sed < ipsec.conf.tmpl > $(NODE2_NAME)/ipsec.conf && \
	    sed -f .node2.sed < ipsec.secrets.tmpl > $(NODE2_NAME)/ipsec.secrets && \
	    echo "LEFT=$(NODE2_NAME)" >> $(NODE2_NAME)/env && \
	    tar zcf  $(NODE2_NAME)-distrib.tgz $(NODE2_NAME) && rm -rf $(NODE2_NAME)
	@echo "Distribution files created:" ; \
	    echo "$(NODE1_NAME)-distrib.tgz" ; \
	    echo "$(NODE2_NAME)-distrib.tgz"

env:
	@echo "Lets create an environment file for your setup"; \
	    echo "" ; \
	    echo "(use a simple name without spaces; eg 'home')" ; \
	    echo -n "Please enter the name for the first end: "; \
	    read NODE1_NAME; \
	    echo -n "Please enter the CIDR subnet for $${NODE1_NAME}: "; \
	    read NODE1_CIDR; \
	    echo -n "Please enter the public IP for $${NODE1_NAME}: "; \
	    read NODE1_PUB; \
	    echo -n "Now enter the name for the second end: "; \
	    read NODE2_NAME; \
	    echo -n "Please enter the CIDR subnet for $${NODE2_NAME}: "; \
	    read NODE2_CIDR; \
	    echo -n "Please enter the public IP for $${NODE2_NAME}: "; \
	    read NODE2_PUB; \
	    echo "NODE1_NAME=$${NODE1_NAME}" > env ; \
	    echo "NODE1_CIDR=$${NODE1_CIDR}" >> env ; \
	    echo "NODE1_PUB=$${NODE1_PUB}" >> env ; \
	    echo "NODE2_NAME=$${NODE2_NAME}" >> env ; \
	    echo "NODE2_CIDR=$${NODE2_CIDR}" >> env ; \
	    echo "NODE2_PUB=$${NODE2_PUB}" >> env
	@echo ""; \
	    echo "You can edit 'env' later if you need to make any changes" ; \
	    echo ""; sleep 2


clean:
	@rm -f *.pem .*.sed *-distrib.tgz
	@rm -rf $(NODE1_NAME) $(NODE2_NAME)
	@docker rmi --force $(IMAGE) 2>/dev/null || /bin/true


# Debugging
print-%: ; @echo $($*)

.PHONY: clean push distrib pki build
