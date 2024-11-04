# For Makefile paths, see:
# See: https://stackoverflow.com/questions/322936/common-gnu-makefile-directory-path
# and https://stackoverflow.com/questions/18136918/how-to-get-current-relative-directory-of-your-makefile

MAKEFILE_PATH := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

.PHONY: checkov
checkov:
# See checkov cli: https://www.checkov.io/2.Basics/CLI%20Command%20Reference.html
# See 'Using docker' https://github.com/bridgecrewio/checkov#using-docker
	docker pull bridgecrew/checkov:latest
	docker run --tty --rm --volume $(MAKEFILE_PATH)/environments:/tf --workdir /tf bridgecrew/checkov --skip-framework kubernetes kustomize --directory /tf

.PHONY: tfsec
tfsec:
# See https://github.com/aquasecurity/tfsec
	docker pull aquasec/tfsec:latest
	docker run --tty --volume $(MAKEFILE_PATH)/environments:/src --rm aquasec/tfsec:latest /src

.PHONY: terrascan
terrascan:
# See https://github.com/tenable/terrascan
	docker pull tenable/terrascan:latest
	docker run --tty --rm --volume $(MAKEFILE_PATH)/environments:/iac --workdir /iac tenable/terrascan  scan --show-passed -t azure -i terraform

.PHONY: fmt
fmt:
	terraform fmt -recursive

.PHONY: step-ca
step-ca:
	STEPPATH=./.step step ca init --deployment-type standalone --name MBSDemoCA --dns localhost --address 127.0.0.1:443 --provisioner MBSDemoCAProvisioner --context mbsdemo

.PHONY: step
step:
	step certificate create client1-authn-ID client1-authn-ID.pem client1-authn-ID.key --ca ./.step/authorities/mbsdemo/certs/intermediate_ca.crt --ca-key ./.step/authorities/mbsdemo/secrets/intermediate_ca_key --no-password --insecure --not-after 2400h
	step certificate create client2-authn-ID client2-authn-ID.pem client2-authn-ID.key --ca ./.step/authorities/mbsdemo/certs/intermediate_ca.crt --ca-key ./.step/authorities/mbsdemo/secrets/intermediate_ca_key --no-password --insecure --not-after 2400h
	step certificate create client3-authn-ID client3-authn-ID.pem client3-authn-ID.key --ca ./.step/authorities/mbsdemo/certs/intermediate_ca.crt --ca-key ./.step/authorities/mbsdemo/secrets/intermediate_ca_key --no-password --insecure --not-after 2400h
	step certificate create client4-authn-ID client4-authn-ID.pem client4-authn-ID.key --ca ./.step/authorities/mbsdemo/certs/intermediate_ca.crt --ca-key ./.step/authorities/mbsdemo/secrets/intermediate_ca_key --no-password --insecure --not-after 2400h
	step certificate create client5-authn-ID client5-authn-ID.pem client5-authn-ID.key --ca ./.step/authorities/mbsdemo/certs/intermediate_ca.crt --ca-key ./.step/authorities/mbsdemo/secrets/intermediate_ca_key --no-password --insecure --not-after 2400h