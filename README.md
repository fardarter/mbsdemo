# MBS IoT Platform Assignment <!-- omit in toc -->

- [Introduction](#introduction)
  - [Limitations](#limitations)
- [Provisioned clients](#provisioned-clients)
  - [Connection details](#connection-details)
- [Dependencies](#dependencies)
  - [Working with secrets in git (Mozilla SOPS)](#working-with-secrets-in-git-mozilla-sops)
    - [Encrypt](#encrypt)
    - [Decrypt](#decrypt)

## Introduction

Greetings! This is a deployment based (mostly) on the blog/talk by Sander Van De Velde (<https://sandervandevelde.wordpress.com/2023/10/14/a-first-look-at-azure-eventgrid-mqtt-support/>),
and the capture component in the IoT concept diagram.

**NOTE!** This prototype does not provide my answer to the case study question of what the `MISSING LINK` should be -- I'll address that in my presentation. Rather, I wanted to:

- explore the topic (which is pretty much entirely new to me) by prototyping; and
- provide some evidence of my project construction, writing and IaC skills.

I have also provided you some clients for play with (configured on the Event Grid namespace `t1mbs-eventgrid-namespace` -- connection details below):

- Senders: `client1`, `client2` (can publish to `device/${client.authenticationName}/telemetry`)
- Receivers: `client3`, `client4`, `client5` (can subscribe to `device/+/telemetry`)

If you'd like to see the data flows in operation, I can deploy a working data capture workflow on Azure in a about 20 minutes (your users will have rights provisioned as part of the deploy). It does cost a little money (mainly the event hub namespace with capture), so give me a bit of warning and I'll put it up (and can leave it up for 4-5 hours; it's about R60 for a full day so it's not a lot -- just don't want to leave it up constantly).

To use the client credentials, please ensure you've accepted my user invitation and run `./setup.ps1` which will log you in and decrypt the client secrets for you in the `./secrets` folder. The authorising intermediate certificate is persisted in a key vault.

The core components I've prototyped are:

- Event Grid set up as an MQTT broker (with certificate authentication and topics set up to prevent spoofing).
- Event Grid routing to Event Hub (with filtering).
- Event Hub with capture configured to a storage account.
- Diagnostic data for all resources sent to a Log Analytics Workspace (`t0-control-plane-law`).
- MQTT system topics routed to Event Hub to track session events.

Most of what you'll be interested in is in resource groups:

- `t1-control-plane`
- `mercedes-benz`

### Limitations

To avoid this project entirely taking over my life:

- Again, this prototype does not reflect my ultimate approach to the `MISSING LINK`.
- There is little to no private networking, network segregation and point-to-point allowlisting.
- There is no IaC layering and (partly because of this) the control plane is not in IaC.
- The certs are toy certificates and no renewal/rotation/provisioning has been considered.
- There are many places where this whole process could be hardened.

However! There is only one static secret, and that is the cert in the vault. Which I'm pleased about, though it's annoying the degree to which some functionality (at first pass) depends on SAS keys.

## Provisioned clients

I made use of the [mttqx client](https://mqttx.app/) working through these problems -- I hope that the connection information provided works well enough if you are using something else.

### Connection details

- Host: `t1mbs-eventgrid-namespace.westeurope-1.ts.eventgrid.azure.net` (in case it changes, search for: `t1mbs-eventgrid-namespace`>). Port is `8883`.
- Protocol: `mqtts://`
- Username scheme: `client*-authn-ID`, eg : `client1-authn-ID`, `client2-authn-ID`
- `.pem` and `.key` files can be found encrypted (or, if you've `az` logged in and run `./setup.ps1`, unencrypted but `.gitignore`d) in `/secrets`.
- Select TLS/SSL authentication and allow for CA or Self-signed and add the secret files.

## Dependencies

I've tried to assume as little as possible in the setup here, but if you don't have `chocolatey` installed and are not operating on Windows (I was told you're a Windows shop anyway), my `setup.ps1` won't work.

Here is the install link for chocolatey if you don't have it: <https://chocolatey.org/install>.

Otherwise, the only dependencies I'll be installing to get you set up with a client connection are (and they'll be run in `./setup.ps1`):

- `choco install sops -y` # for secret encryption/decryption -- there's a section on usage in this `README.md` for your interest.
- `choco install azure-cli -y`
# Introduction

## Notes

### Working with secrets in git (Mozilla SOPS)

For reference, see [Encrypting using Azure Key Vault](https://github.com/mozilla/sops#encrypting-using-azure-key-vault).

To use SOPS, you must have the `az-cli` tool installed and you must have RBAC rights to a key stored in an azure key vault, specifically for decryption the one used to encrypt the file.

Key info is stored in the encrypted file, in the case of Azure, like so:

```json
"azure_kv": [
  {
    "vault_url": "https://t1mbs-kv.vault.azure.net",
    "name": "sops-demo",
    "version": "5cd32a5764354d119c84d598c01d95d3",
    "created_at": "2022-06-28T11:28:12Z",
    "enc": "AH132u-tdCK4AgkDEQPLb_rEhNymjVjHaUFddw8HJknqSQZlSao7y6hDFoRgLbkLUuExVbCj4ygT-kI7AMD0D7vc3cSkGPB37h8SAXU29k1jer4BapJqeABKZBwMl27-rlUXKbMCR99v9uJGjdHY3HfWawvgPcSbtcXz1hSSt9u2eeUORQt_U2jpk3TBft4CwyC-5QgsAu45nusaIgyevgZDGd9w8bUx8fcOgbTq4IOsJtn6BhkqIynyt_pVFi3Zl4QUXR8S4oekUSXhQQx1o0SwPwcHgYrJ-iwOdi9FRy0TsamhxCxzyte8aCfzHTUiSLkNQtt0I43SahtjcGDJVNkDxuGumP2n1DE3-xAdzdoI6aekM6kl7hQZHo5murWS5XGNJXPdBsUxBKkAiiK3CeRP3yJJ8RDvb3C92VVP11NIUhd8_lTxyp1HpmsS5t2TUuyIPkhkSWhrbjz454EkSW07L6Ubtcz88a_1e60nI0Fg1mA5TO0PYy260ytc0cVG9JzoLanEzMJfS9pIoE-CPr9okc4XHnAi88m-bbL76rqQ1IwTSRH3oH5oyL5Vy357LWESl6wjK5stVE3Bx7DKlCL7KC34EiHy3ahYwG6xbWHLh0lTPCUjyRhQu5l4k5EMX7E3Fk2LbvjYlsueJXgy4z8AdxgIfKrCnElW5c8KJsQ"
  }
]
```

#### Encrypt

To get the key ID programmatically:

```sh
# az keyvault key show --name <keyname> --vault-name <vaultname> --query key.kid
az keyvault key show --name sops-demo --vault-name t1mbs-kv --query key.kid
```

To encrypt a file:

```ps
# sops --encrypt --azure-kv https://<vault-url>/keys/<keyname>/<keyID> <filename.extension> | Out-File -Encoding "UTF8" -FilePath "<filename.enc.extension>"
sops --encrypt --azure-kv "https://t1mbs-kv.vault.azure.net/keys/sops-demo/5cd32a5764354d119c84d598c01d95d3" "client1-authn-ID.key"  | Out-File -Encoding "default" -FilePath "client1-authn-ID.enc.key"
```

> OR

```sh
sops --encrypt --azure-kv https://t1mbs-kv.vault.azure.net/keys/sops-demo/5cd32a5764354d119c84d598c01d95d3 client1-authn-ID.key > client1-authn-ID.enc.key
```

#### Decrypt

```ps
sops -d client1-authn-ID.enc.key | Out-File -Encoding "default" -FilePath client1-authn-ID.key
```

> OR

```sh
sops -d client1-authn-ID.enc.key > client1-authn-ID.key
```

> **Note**: If you get an empty file on output, it (usually) means you've done something wrong in decryption.
