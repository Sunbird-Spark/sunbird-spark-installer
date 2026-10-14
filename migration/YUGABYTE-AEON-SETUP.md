# YugabyteDB Aeon setup (after the Azure Marketplace purchase)

Steps to go from the Azure Marketplace purchase to the platform running on a managed YugabyteDB Aeon cluster, for the **test** environment (AKS cluster `ed-test`).

**Starting point:** the Aeon subscription is already bought on the Azure Marketplace:

| Item | Value |
|---|---|
| Plan | YugabyteDB Aeon — Pay as you go |
| Azure subscription | `OneClickInstallation` |
| Resource group of the purchase | `YugabyteDB_Aeon` |

**Aeon is fully managed.** You don't create VMs. You create the cluster at **cloud.yugabyte.com**, and Yugabyte runs it in **their** Azure account. The `YugabyteDB_Aeon` resource group only holds the Marketplace **billing record**: no VMs, disks or network.

**Where each step happens:**

| # | Step | Where |
|---|---|---|
| 1 | Link the purchase to an Aeon account | Azure portal → cloud.yugabyte.com |
| 2 | Turn on auto-renew | Azure portal |
| 3 | Create the Aeon VPC | cloud.yugabyte.com |
| 4 | Create the cluster | cloud.yugabyte.com |
| 5 | Allow your subscription to connect (Private Service Endpoint) | cloud.yugabyte.com |
| 6 | Create the private endpoint in the AKS VNet | Azure portal (resource group **`ed-test`**) |
| 7 | Create the private DNS zone | Azure portal (resource group **`ed-test`**) |
| 8 | Test the connection | installer VM + AKS |
| 9 | Point the platform at the cluster | `global-values.yaml` + `install.sh` |

Steps 3–7 can also be done in one go by the `yugabyte-managed` OpenTofu module on this branch (see [the alternative at the end](#alternative-steps-37-with-the-yugabyte-managed-module)).

**Test environment values:**

| Item | Value |
|---|---|
| Azure subscription | `OneClickInstallation` (`ace365b8-6378-40cc-99f6-e021f02e5905`) |
| Region | Central India (`centralindia`) |
| AKS resource group | `ed-test` |
| VNet / AKS subnet | `ed-test` / `ed-test-aks` |

---

## 1. Link the purchase to an Aeon account

1. In the Azure portal, open the Marketplace purchase (resource group `YugabyteDB_Aeon`).
2. Click **Open SaaS Account on publisher's site**. This opens **cloud.yugabyte.com**.
3. Sign in with the organisation's account (or sign up). This links the Azure purchase to the Aeon account.
4. In cloud.yugabyte.com → **Usage & Billing**, check that billing shows **Azure Marketplace**. If it asks for a credit card, the link didn't complete: go back to the Azure portal and click **Open SaaS Account on publisher's site** again.

## 2. Turn on auto-renew

The purchase has **Auto-renew: Off** and **expires on 14/11/2026**. If it expires, Aeon billing stops and the cluster can be paused or deleted.

1. Azure portal → the Marketplace purchase → **Edit Auto-renew** → **On** → **Save**.

## 3. Create the Aeon VPC

In cloud.yugabyte.com:

1. **Networking → VPC Network → VPCs → Create VPC**.
2. **Name:** `ed-test-aeon-vpc`.
3. **Provider:** Azure. **Region:** Central India.
4. **CIDR:** keep the automatic range, or pick one that doesn't overlap the AKS VNet (`10.0.0.0/16`).
5. **Save** and wait for status **Active**.

## 4. Create the cluster

In cloud.yugabyte.com:

1. **Clusters → Add Cluster → Dedicated**.
2. **General:** name `ed-test-yb`, Provider **Azure**, Database Version **2025.2 or newer** (the in-cluster version is `2025.2.0.0`).
3. **Cluster Settings:** **Single-Region Deployment**.
4. **Fault Tolerance:** **Availability Zone level** (3 nodes across 3 zones).
5. **Region and size:** Central India, **3 nodes**, **4 vCPU per node**, **~85 GB disk per node**. vCPU and nodes can be changed later; disk can only grow.
6. **VPC:** `ed-test-aeon-vpc` from step 3.
7. **Database:** keep the defaults.
8. **Network Access:** skip for now (step 5).
9. **Database Credentials:** set the admin **username** and **password**, and download the credentials file. The password is shown only once. The same user works for YSQL and YCQL.
10. **Create Cluster** and wait for status **Active** (several minutes).
11. Cluster → **Connect** → **Download CA Cert**. Save it as `root.crt`.

## 5. Allow your subscription to connect (Private Service Endpoint)

The cluster is in Yugabyte's network, and your AKS cluster is in yours. A Private Service Endpoint lets your subscription reach the cluster privately.

In cloud.yugabyte.com:

1. Cluster → **Settings → Network Access → Private Service Endpoint → Create Private Service Endpoint**.
2. Region **Central India**, subscription ID `ace365b8-6378-40cc-99f6-e021f02e5905`. **Save**.
3. Wait for **Active**, then note:
   - **Service Name** (an Azure Private Link alias), used in step 6
   - **Host** (ends in `.azure.yugabyte.cloud`, e.g. `pse-centralindia.<cluster-id>.azure.yugabyte.cloud`). This is the database **URL** the platform will use.

## 6. Create the private endpoint (Azure portal)

This puts a private IP for the Aeon cluster inside the AKS VNet.

1. **Private endpoints → + Create**.
2. **Basics:** subscription `OneClickInstallation`, resource group **`ed-test`** (not `YugabyteDB_Aeon`), name `ed-test-aeon-pe`, region **Central India**.
3. **Resource:** **Connect to an Azure resource by resource ID or alias** → paste the **Service Name** from step 5.
4. **Virtual Network:** VNet **`ed-test`**, subnet **`ed-test-aks`**, private IP **dynamic**.
5. **DNS:** **No** private DNS zone integration (step 7 does it).
6. **Review + create → Create**.
7. Open the endpoint and check **Connection status: Approved**. If it shows **Pending**, recheck the subscription ID in step 5.
8. Open the endpoint's **network interface** and note its **private IP** (e.g. `10.0.x.x`).

## 7. Create the private DNS zone (Azure portal)

This makes the Aeon host name from step 5 resolve to the private IP from step 6, inside the VNet.

1. **Private DNS zones → + Create**: resource group **`ed-test`**, name **`azure.yugabyte.cloud`** (exactly this). **Review + create → Create**.
2. Open the zone → **Settings → Virtual network links → + Add**: name `ed-test-vnet-link`, VNet **`ed-test`**, auto-registration **off**. **OK**.
3. **Overview → + Record set**:
   - **Name:** the Host from step 5 without `.azure.yugabyte.cloud` (for `pse-centralindia.abc123.azure.yugabyte.cloud`, enter `pse-centralindia.abc123`)
   - **Type:** A
   - **IP address:** the private IP from step 6

## 8. Test the connection

From the installer VM:

```bash
nslookup <aeon-host>        # must return the private IP from step 6
nc -zv <aeon-host> 5433     # YSQL
nc -zv <aeon-host> 9042     # YCQL
ysqlsh "host=<aeon-host> port=5433 dbname=yugabyte user=<aeon-user> sslmode=verify-full sslrootcert=root.crt" -c "SELECT version();"
```

From inside AKS:

```bash
kubectl -n sunbird run aeon-test --rm -it --restart=Never --image=busybox -- \
  sh -c "nslookup <aeon-host>; nc -zv <aeon-host> 5433; nc -zv <aeon-host> 9042"
```

If `nslookup` returns a public IP or nothing, recheck step 7.

## 9. Point the platform at the cluster

In the environment's `global-values.yaml` (private repo / installer VM, never this public repo):

```yaml
global:
  yugabyte_managed:
    enabled: true
    host: "<aeon-host>"         # Host from step 5
    port: 9042
    postgresql_port: 5433
    username: "<aeon-user>"     # from step 4
    password: "<aeon-password>"
    ca_cert: |                  # contents of root.crt from step 4.11
      -----BEGIN CERTIFICATE-----
      MIID...
      -----END CERTIFICATE-----
```

**`ca_cert`:** open `root.crt` in a text editor and paste the **whole** content, including the `BEGIN` and `END` lines, under `ca_cert: |`. Indent every line 2 spaces deeper than `ca_cert`. Aeon requires TLS, so don't leave it empty for Aeon.

When `enabled: true` **and** `ca_cert` is set, each bundle creates a secret `<bundle>-yugabyte-ca` with the certificate and mounts it at `/etc/yugabyte-tls/root.crt` in:

| Service | How it uses the certificate |
|---|---|
| Kong (and its migrations job) | `KONG_PG_SSL_VERIFY=on`, `KONG_LUA_SSL_TRUSTED_CERTIFICATE` |
| Keycloak, registry | JDBC URL `sslmode=verify-ca&sslrootcert=/etc/yugabyte-tls/root.crt` |
| Superset (web, worker, beat, init) | database URI `sslmode=verify-ca&sslrootcert=…` |
| Player (portal, SQL) | `PGSSLMODE=verify-ca`, `NODE_EXTRA_CA_CERTS` |
| keycloak-kids-keys, YSQL migration jobs | `PGSSLMODE=verify-ca`, `PGSSLROOTCERT` |
| YCQL migration jobs | `ycqlsh` over SSL (`cqlshrc`) |
| JanusGraph (and its schema-init job) | Java truststore built from the certificate; `storage.cql.ssl.*` plus the Aeon username/password |

With `enabled: false`, or `ca_cert` empty, nothing is mounted and nothing changes.

Then redeploy the bundles:

```bash
./install.sh install_component edbb
./install.sh install_component learnbb
./install.sh install_component knowledgebb
./install.sh install_component obsrvbb
./install.sh install_component additional
```

With `enabled: true`, every building block and addon connects to the Aeon host, and `install.sh` doesn't deploy the in-cluster YugabyteDB or `yugabyte-backup`. Set `enabled: false` to go back to the in-cluster YugabyteDB.

**Before this works end to end:** the services in the table above get TLS from the chart. These still connect to YCQL **without TLS or credentials**, because their application code has no option for it: lern, certregistry, the Flink jobs, knowlg, sync-tool, knowledge-mw, the portal's forms and review comments, and the addons. They need code changes before the platform runs fully on Aeon. See part 1 of the migration guide (`migration/YUGABYTE-TO-MANAGED.md` on the `feat/external-cassandra-postgres` branch). Moving existing data into Aeon is covered there too (part 7).

---

## Alternative: steps 3–7 with the `yugabyte-managed` module

The OpenTofu module `opentofu/azure/modules/yugabyte-managed` creates the Aeon VPC, the cluster, the Private Service Endpoint, the private endpoint, the DNS zone, the VNet link and the A record in one apply. Steps 1–2 (linking and auto-renew) still have to be done by hand first.

1. **Aeon API key:** cloud.yugabyte.com → **Usage & Billing → API Keys** → create a key.
2. In the environment's `global-values.yaml`:

   ```yaml
   global:
     yugabyte_managed_auth_token: "<aeon-api-key>"
     yugabyte_managed_db_username: "<aeon-user>"
     yugabyte_managed_db_password: "<aeon-password>"
   ```

3. Apply it (not part of `install.sh`; run it after `create_tf_resources`):

   ```bash
   cd ~/sunbird-spark-installer/opentofu/azure/test
   source tf.sh
   cd yugabyte-managed && terragrunt apply && cd ..
   ```

4. Get the database URL:

   ```bash
   cd yugabyte-managed && terragrunt output -raw private_host && cd ..
   ```

   Use it as `host` in step 9.
5. Download the CA certificate (step 4.11) and check the private endpoint `test-yugabyte-pe` shows **Approved** in the Azure portal.
