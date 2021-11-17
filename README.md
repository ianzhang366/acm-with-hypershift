
Usage: ./demo.sh [options]
	./demo.sh help you deploy a hosted cluster, then import the hosted cluster to your ACM hub,
	and provide helper functions to clean up and show some entry points

	-c	create hosted cluster(on AWS) and imported it to ACM hub
	-d	detach the hosted cluster from ACM hub and destroy the hosted cluster
	-r	render will output the hypershift CRs to YAML file for you to inspect
	-s	show routes to hosted cluster's OCP console and your ACM hub

Note: this script assums, you put the kubeconfig to your ACM huh at ./mgmt-kubeconfig
