# vpn-toolkit

This repo contains utilities for establishing a net-to-net VPN between
two environments.  Everything is wrapped in docker containers to make
it easier to set up, and has been tested on x86 and Raspberry PIs.

# Dependencies

* Make
* Docker 17.05 or newer
* docker-compose 1.13 or newer
* Known public IPs for both endpoints (both can be behind NAT though)
* Tested with raspbian and debian/ubuntu

# NAT Limitations

This VPN stack works by using UDP, and typical NAT router setups where
outbound UDP packets will open up the port for inbound response packets.
As long as both ends know the public IP address of the other end,
then they'll both start sending a stream of UDP packets to eachother,
and the NAT will allow the other ends packets through as "responses."

This means you can only run **one** VPN endpoint behind a given NAT.  If you
tried to run two then since UDP is stateless, the NAT router wouldn't know which
internal VPN endpoint to route responses to.

# Setup

Before you get started, you'll need to set up an `env` file which defines
the basic characteristics of your two endpoints.  You'll need to name
each end, and know the subnets, and public IP addresses for them.

Run the following and you'll be prompted to name each endpoint, and define
the key network attributes needed to set up the VPN link:
```
make env
```
(If you make any mistakes, you can edit the `env` file later)

# PKI

Before we get started, you'll need to establish your certificates for
a secure environment.  Once you run this target, you'll have generated a set of secret
keys which you need to keep safe.

```
make build
make pki
```

# Distribute

Now we need to copy the essential files (without the ca private key for security) to each
of the endpoints that will be running the VPN stack.

The following command will create two tar files, named after your two endpoints, with
all the settings wired up.

```
make distrib
```

Now copy the tar files to the two endpoints, expand and bring up the links.

**You will need to bring both up at the same time if you have NAT** Both
ends must start sending the UDP packets concurrently to get through the
NAT layers.

On each end do the following:
```
make build
docker-compose up
```

# Routing

On both of your NAT routers, you'll need to set up a static route for
the remote network that uses the local VPN endpoint as the gateway.
If you skip this step, the two endpoints will be able to communicate,
but wont be able to reach other systems on the two networks.

TODO - put a diagram here to better explain with an example.


# Troubleshooting

After running the `docker-compose up` you can exec into the containers with something like `docker exec -it ${ENDPOINT_NAME}_vpn_1 sh` (replace `${ENDPOINT_NAME}` with the actual name) and then you can run
various diagnostic commands.
```
ipsec status
ipsec statusall
ipsec listcerts
ip xfrm policy
```

You can also run `tcpdump` on both ends and try `ping` to the other
endpoints private IP, or some other private IP on the other end.

# TODO

* Support dynamic public IPs on the endpoints by supporting a public DDNS
  service or another endpoint that does have a fixed hostname/IP.
* Support multiple VPN links with a single endpoint to establish a connected mesh
