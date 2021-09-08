# Minetest Game Server Example for Agones

Dedicated [Minetest](https://www.minetest.net/) Game Server hosting on Kubernetes using [Agones](https://agones.dev/site/). 

This example wraps the Minetest server with a [Go](https://golang.org) binary, and introspects
stdout to provide the event hooks for the SDK integration. The wrapper is from [Xonotic Example](https://github.com/googleforgames/agones/blob/main/examples/xonotic/main.go) with a few changes to look for the Minetest ready output message.

It is not a direct integration, but is an approach for to integrate with existing
dedicated game servers.

You will need to download the Minetest client separately to play.
