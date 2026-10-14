# Migrate from in-cluster YugabyteDB to YugabyteDB Aeon

This guide moves the **test** environment (`dev.sunbirded.org`, AKS cluster `ed-test`) from the YugabyteDB that runs inside AKS to **YugabyteDB Aeon**, Yugabyte's managed service.

---

## Order of work (read this first)

Do the parts **in this order**. Each part needs the one before it.

| # | Part | Where | What you get out of it |
|---|---|---|---|
| 1 | [Prepare](#part-1--prepare) | code | services able to use TLS |
| 2 | [Buy Aeon](#part-2--buy-aeon-through-the-azure-marketplace) | Azure portal | Aeon account billed through Azure |
| 3 | [Create the Aeon VPC](#part-3--create-the-aeon-vpc) | Aeon console | a private network on Yugabyte's side |
| 4 | [Create the cluster](#part-4--create-the-cluster) | Aeon console | the database, admin user, CA certificate |
| 5 | [Connect the network](#part-5--connect-the-network-private-link) | Aeon console + Azure portal | a private path from AKS to Aeon |
| 6 | [Test the connection](#part-6--test-the-connection) | installer VM + AKS | proof that AKS can reach Aeon |
| 7 | [Migrate the data](#part-7--migrate-the-data) | installer VM | data copied into Aeon (**downtime**) |
| 8 | [Switch the platform to Aeon](#part-8--switch-the-platform-to-aeon) | `global-values.yaml` + `install.sh` | services running on Aeon |

**Why the VPC comes before the cluster:** a cluster can only be put in a VPC while it's being created.
**Why the network comes after the cluster:** the private endpoint (part 5) is created per cluster, so the cluster must exist first.

Parts 2–6 can be done days ahead with **no downtime**. Downtime only starts in part 7.

---

## Basics

| Term | Meaning |
|---|---|
| **YugabyteDB** | The database Sunbird uses. It speaks two languages: **YSQL** (Postgres-compatible, port 5433) and **YCQL** (Cassandra-compatible, port 9042). |
| **In-cluster YugabyteDB** | What runs today: pods inside AKS, installed by the `edbb` Helm chart, reached at `yb-tserver-service`. |
| **YugabyteDB Aeon** | Yugabyte's managed service. Yugabyte runs the database in their own Azure account; you get a host name to connect to. |
| **Aeon VPC** | A private network on Yugabyte's side that the cluster lives in. |
| **Private Link** | Azure's way to reach a service in another account privately, without the internet. On Azure it's the **only** private option for Aeon (no VNet peering). |
| **Private Service Endpoint (PSE)** | The Aeon side of Private Link: it publishes your cluster so your Azure subscription can connect. |
| **Private Endpoint** | The Azure side of Private Link: a private IP inside the AKS VNet that leads to the Aeon cluster. |
| **Private DNS zone** | Makes the Aeon host name resolve to that private IP inside the VNet. |
| **TLS** | Encryption of the database connection, like HTTPS for a browser. **Aeon requires it**; today's services connect without it. |
| **CA certificate (`root.crt`)** | File from Aeon that services use to verify they're really talking to your Aeon cluster over TLS. |

**Test environment values used throughout:**

| Item | Value |
|---|---|
| Azure subscription | `OneClickInstallation` (`ace365b8-6378-40cc-99f6-e021f02e5905`) |
| Region | Central India (`centralindia`) |
| Resource group | `ed-test` |
| AKS cluster | `ed-test` |
| VNet / AKS subnet / installer VM subnet | `ed-test` / `ed-test-aks` / `ed-test-runner` |
| Storage account / private container | `edtestace365b8` / `ed-test-private-6b89b2952a` |
| In-cluster YugabyteDB user | `yugabyte` |

---

## Part 1 — Prepare

### 1a. Can we do it?

- **Moving the data: yes.** A logical dump and restore works, and the existing `yugabyte-backup` job already produces the dump files.
- **Running the platform on Aeon: only after the TLS changes in 1b.** Without them, the data migrates but the services can't connect.
- Snapshot copy (`yb-admin`) and xCluster replication don't work from a self-managed cluster into Aeon. A logical dump is the only option, and it needs downtime.

### 1b. Make the services able to use TLS

**Why:** today the database is inside the AKS network, so services connect without encryption. Aeon is outside it, so it **requires TLS on every connection** and rejects unencrypted ones. Aeon's YCQL also **requires a username and password**, which some services don't send today.

Each service needs: TLS turned on in its database connection, plus Aeon's CA certificate (`root.crt`) mounted so it can verify the server.

Checked against the installer's **`main`** branch (what the test environment runs) and the application source (`release-8.1.0`):

**YSQL services — chart configuration only**

| Service | Setting that holds the database address (`main`) | TLS change |
|---|---|---|
| Kong | `edbb/charts/kong/configs/env.yaml`: `KONG_PG_HOST` / `KONG_PG_PORT` ← `global.yugabyte.host` / `postgresql_port` | already `KONG_PG_SSL: "True"`; add `KONG_PG_SSL_VERIFY: "on"` and `KONG_LUA_SSL_TRUSTED_CERTIFICATE` pointing at the mounted `root.crt` |
| Keycloak | `learnbb/charts/keycloak/configs/env.yaml`: `KC_DB_URL: jdbc:postgresql://<host>:<postgresql_port>/keycloak?sslmode=disable` | change `sslmode=disable` → `sslmode=require` (or `verify-full&sslrootcert=/path/root.crt`) |
| Registry | `learnbb/charts/registry/configs/env.yaml`: `connectionInfo_uri: jdbc:postgresql://<host>:<postgresql_port>/registry` | append `?sslmode=require` |
| Portal / player (SQL) | `edbb/charts/player/configs/env.yaml`: `SUNBIRD_YUGABYTE_HOST` / `SUNBIRD_YUGABYTE_PORT` | add env `PGSSLMODE=require` (the portal's `pg` pool sets no `ssl` option, so it reads this variable); add `NODE_EXTRA_CA_CERTS=/path/root.crt` |
| lern (Postgres side) | `learnbb/charts/lern/configs/env.yaml`: `sunbird_postgres_host` / `sunbird_postgres_port` | add `sslmode=require` to its JDBC settings (verify in lern's Postgres client) |
| keycloak-kids-keys job | `learnbb/charts/keycloak-kids-keys/configs/env.yaml`: `YUGABYTE_HOST` / `YUGABYTE_PORT` | add env `PGSSLMODE=require` |
| Superset | `obsrvbb/charts/superset/templates/secret-env.yaml`: `DB_HOST` / `DB_PORT` ← `global.yugabyte.host` / `postgresql_port`, user/password ← `global.yugabyte.ysql.user` / `ysql.password` | add env `PGSSLMODE=require` (psycopg2 reads it) |

**YCQL services**

| Service | Setting that holds the database address (`main`) | TLS + credentials change | Type |
|---|---|---|---|
| JanusGraph | **hardcoded** in `knowledgebb/charts/janusgraph/values.yaml`: `storageBackend.external.hostname: "yb-tserver-service"`, `port: "9042"`; also `config/janusgraph-cql.properties`: `storage.hostname=yb-tserver-service` | add `storage.cql.ssl.enabled=true`, `storage.cql.ssl.truststore.location` / `password` (truststore built from `root.crt`), `storage.username` / `storage.password` | chart config |
| lern | `learnbb/charts/lern/configs/env.yaml`: `sunbird_cassandra_host` / `sunbird_cassandra_port` | **confirmed:** `userorg-service` `CassandraConnectionManagerImpl.createCluster()` has no SSL option and no credentials | code |
| certregistry | `learnbb/charts/certregistry/configs/env.yaml`: `sunbird_cassandra_host` / `sunbird_cassandra_port` | same connection pattern as lern | code (likely) |
| Flink jobs (learnbb, knowledgebb) | `learnbb/charts/flink/values.yaml`, `knowledgebb/charts/flink/values.yaml`: `host` / `port` ← `global.yugabyte.*` | **confirmed:** `data-pipeline` `CassandraUtil` builds `Cluster.builder().addContactPoint(host)` with no SSL and no credentials | code |
| knowlg, sync-tool | `knowledgebb/charts/knowlg/configs/application.conf`: `cassandra.lp.connection`, `cassandra.lpa.connection`, `graph.storage.hostname` / `port`; `sync-tool/configs/application.conf`: `graph.storage.hostname` / `port` | JanusGraph part: config (as above); Cassandra part: not verified, most likely like lern | config + code (likely) |
| knowledge-mw | `edbb/charts/knowledgemw/configs/env.yaml`: `sunbird_cassandra_urls: <host>:<port>` | no TLS/credentials setting in the chart | code (likely) |
| Portal forms / review comments | `edbb/charts/player/configs/env.yaml`: `SUNBIRD_YUGABYTE_HOST` (+ `SUNBIRD_YUGABYTE_YCQL_PORT`) | **confirmed:** `sunbird-spark-portal` `formsDatabase.ts` / `reviewCommentDatabase.ts` create the client without `sslOptions` or credentials | code |
| Addons (dial, groups, video-stream-generator, asset-enrichment) | `addons/global-values.yaml`: `global.yugabyte.host` / `port` | same pattern as lern / Flink | code (likely) |

**In short:**
- Pointing services at Aeon is one flag: `global.yugabyte_managed.enabled: true` plus the host, user and password (part 8.1). The charts and `install.sh` handle the rest.
- TLS for YSQL services is chart configuration.
- TLS and credentials for YCQL services need **code changes** in lern, certregistry, the Flink jobs, knowlg, knowledge-mw, the portal and the addons. Only JanusGraph can do it through configuration.

Finish and test these changes on a non-production environment before part 7.

---

## Part 2 — Buy Aeon through the Azure Marketplace

Buying through the Azure Marketplace puts Aeon's charges on the **Azure invoice** of `OneClickInstallation`: no separate card or contract with Yugabyte. It also counts towards an Azure spend commitment (MACC), if your organisation has one.

**Who can do it:** a user with **Owner** or **Contributor** on the subscription. If Marketplace purchases are restricted (private marketplace), a billing admin has to allow the YugabyteDB offer first.

1. In the **Azure portal**, open **Marketplace** and search for **YugabyteDB Aeon** (publisher: Yugabyte).
2. Open the offer, choose the plan, and click **Subscribe**:
   - **Billing model: pay-as-you-go.** Billed monthly for actual use (vCPU-hours and disk), no commitment. Right for the test environment and the migration. For production, once usage is stable, ask Yugabyte for an **annual private offer** (a discount for a yearly commitment, still billed through the Marketplace).
   - **Tier: Professional** (chosen, for multi-region). The options:

     | Tier | Price | Regions | What it includes |
     |---|---|---|---|
     | Standard | ~$125/vCPU/month | **single region only** | YSQL and YCQL, Private Link, 24/7 support |
     | **Professional** (chosen) | ~$167/vCPU/month | **single or multi-region** | everything in Standard, plus multi-region clusters (replicate across regions, partition by region, read replicas), Performance Advisor, metrics export |
     | Enterprise | custom quote | single or multi-region | everything in Professional, plus SSO, customer-managed keys, Bring Your Own Cloud |

     Private Link is included in all tiers ("Core Security and Networking" on Yugabyte's pricing page).

     **Cost at 3 nodes × 4 vCPU plus ~250 GB disk:** Standard ~$1,525/month, **Professional ~$2,029/month**. A multi-region cluster also pays cross-region data transfer (~$0.08/GB within Asia-Pacific, beyond a free allowance of 10 GB/vCPU/month), and more nodes if you place more than one per region.
3. **Basics** page:
   - **Subscription:** `OneClickInstallation`
   - **Resource group:** `ed-test`
   - **Name:** `ed-test-yugabyte-aeon`
   - **Recurring billing:** On
4. **Review + subscribe → Subscribe**. Azure creates a SaaS resource.
5. When it finishes, click **Configure account now**. This opens Yugabyte's page to **link the Marketplace subscription to an Aeon account**. Sign in with your organisation's account, or sign up. This link is what makes Aeon bill through Azure.
6. Open the Aeon console (**https://cloud.yugabyte.com**) → **Usage & Billing**. It should show billing **through the Azure Marketplace**. If it asks for a credit card, the link didn't complete: reopen the SaaS resource in Azure and click **Configure account** again.

Plan names and prices on the Marketplace can change. Check the offer page before subscribing.

---

## Part 3 — Create the Aeon VPC

In the Aeon console:

1. **Networking → VPC Network → VPCs → Create VPC**.
2. **Name:** `ed-test-aeon-vpc`.
3. **Provider:** Azure. **Region:** Central India. For a **multi-region** cluster, create the VPC as **multi-region** and add the same regions you'll use in part 4.
4. **CIDR:** keep the automatic range, or pick one that doesn't overlap the AKS VNet (`10.0.0.0/16`).
5. **Save**, and wait until the status is **Active**.

---

## Part 4 — Create the cluster

In the Aeon console:

1. **Clusters → Add Cluster → Dedicated** (Sandbox is free but can't use a VPC or Private Link).
2. **General:** name `ed-test-yb`, Provider **Azure**, Security Profile **Standard**, Database Version **2025.2 or newer** (the in-cluster version is `2025.2.0.0`; the target must be the same or newer).
3. **Cluster Settings:** choose the deployment type:

   | Option | Tier | What it does | Use it when |
   |---|---|---|---|
   | Single-Region Deployment | Standard or Professional | 3 nodes in Central India, spread across 3 availability zones | you only need to survive a zone failure |
   | **Multi-Region: Replicate across regions** | Professional | one copy of the data in each of 3 regions; the cluster keeps running if a whole region goes down | you need to survive a **region** failure (the usual multi-region choice) |
   | Multi-Region: Partition by region | Professional | each row lives in a chosen region (geo-partitioning) | data must stay in a specific region, or users in different regions need local writes |
   | Read replicas | Professional | a primary cluster plus read-only copies in other regions | you need fast reads far away, but writes can stay in one region |

   For **Replicate across regions**:
   - **Primary region:** **Central India**, the same region as AKS. Set it as the **preferred region**, so reads and writes are served there first.
   - **Two more regions:** pick two other Azure regions that Aeon offers for your account (for example in India or nearby). The Aeon console lists only the regions available to you.
   - **Fault tolerance:** **Region level**.
   - Writes have to reach a second region before they're confirmed, so they're slower than in a single-region cluster. Keep the regions close to each other.

4. **Fault Tolerance:** **Availability Zone level** for single region (3 nodes across 3 zones, matching today's replication factor 3); **Region level** for replicate across regions.
5. **Size:** **4 vCPU per node** (16 GB RAM), disk **~85 GB per node**. For single region, 3 nodes in Central India; for multi-region, at least 1 node per region (3 in total), or more per region for extra capacity. vCPU and node count can be changed later; disk can only grow.
6. **VPC:** select `ed-test-aeon-vpc` from part 3. For a multi-region cluster, the VPC must cover every region you chose: create it as a multi-region VPC in part 3, with the same regions.
7. **Database:** keep the defaults.
8. **Network Access:** skip; part 5 adds the private endpoint.
9. **Security:** enable encryption at rest if your policy requires it.
10. **Database Credentials:** set the admin user and password, and **download the credentials file**. The password is shown only once. The same admin user works for YSQL and YCQL.
11. **Create Cluster.** Wait for status **Active** (several minutes).
12. Open the cluster → **Connect** → **Download CA Cert**. Save it as `root.crt`. You need it in parts 6–8.

---

## Part 5 — Connect the network (Private Link)

### 5a. Create the Private Service Endpoint (Aeon console)

1. Open the cluster → **Settings → Network Access → Private Service Endpoint → Create Private Service Endpoint**.
2. For **Central India**, enter the subscription ID allowed to connect: `ace365b8-6378-40cc-99f6-e021f02e5905`. **Save**.
   For a **multi-region** cluster, Aeon creates one endpoint per region. AKS runs only in Central India, so the **Central India endpoint is the one you need**; the platform connects through it, and the cluster replicates to the other regions internally. Create endpoints in other regions only if something running in those regions also needs to connect.
3. Wait for **Active**, then note:
   - **Service Name**: the Azure Private Link alias (used in 5b)
   - **Host**: ends in `.azure.yugabyte.cloud`, e.g. `pse-centralindia.<cluster-id>.azure.yugabyte.cloud`. This is the Aeon host used everywhere from now on.

### 5b. Create the Private Endpoint (Azure portal)

1. **Private endpoints → + Create**.
2. **Basics:** subscription `OneClickInstallation`, resource group `ed-test`, name `ed-test-aeon-pe`, network interface name `ed-test-aeon-pe-nic`, region **Central India**.
3. **Resource:** **Connect to an Azure resource by resource ID or alias** → paste the **Service Name** from 5a.
4. **Virtual Network:** VNet **`ed-test`**, subnet **`ed-test-aks`**, private IP **dynamic**. This puts the endpoint in the same VNet as AKS and the installer VM.
5. **DNS:** **No** private DNS zone integration (the zone is created by hand in 5c).
6. **Review + create → Create**.
7. Open the endpoint and check **Connection status: Approved**. If it's **Pending**, recheck the subscription ID in 5a.
8. Open the endpoint's **network interface** and note its **private IP** (e.g. `10.0.x.x`).

### 5c. Create the private DNS zone (Azure portal)

1. **Private DNS zones → + Create**: resource group `ed-test`, name **`azure.yugabyte.cloud`** (exactly this: it's Yugabyte's domain). **Review + create → Create**.
2. Open the zone → **Settings → Virtual network links → + Add**: name `ed-test-vnet-link`, subscription `OneClickInstallation`, VNet **`ed-test`**, auto-registration **off**. **OK**.
3. **Overview → + Record set**:
   - **Name:** the Host from 5a without `.azure.yugabyte.cloud` (for `pse-centralindia.abc123.azure.yugabyte.cloud`, enter `pse-centralindia.abc123`)
   - **Type:** A
   - **IP address:** the private IP from 5b.8

AKS pods, the installer VM (same VNet), and laptops on the Pritunl VPN (which uses Azure DNS `168.63.129.16`) now resolve the Aeon host to the private IP.

**Azure cost of these pieces:** private endpoint ~$7.30/month plus $0.01/GB, DNS zone ~$0.50/month.

**Alternative without Private Link (not recommended):** Aeon → **Network Access → IP Allow List**: add the AKS outbound IPs (`az aks show -g ed-test -n ed-test --query "networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id" -o tsv`, then `az network public-ip show --ids <id> --query ipAddress -o tsv`) and the installer VM's public IP, and use the cluster's public host from **Connect**. Traffic then crosses the internet (still encrypted by TLS).

### 5d. Automated alternative for parts 3–5 (`yugabyte-managed` module)

Instead of doing parts 3–5 by hand, the OpenTofu module `opentofu/azure/modules/yugabyte-managed` creates all of it in one apply: the Aeon VPC, the cluster (3 nodes × 4 vCPU, zone fault tolerance, Central India), the Private Service Endpoint, the Azure Private Endpoint, the private DNS zone, the VNet link and the A record. It's on the `benchamarking` branch (commit `e9fb2189`) and isn't merged into `main` yet.

It **does not** cover part 2 (buying Aeon) or the multi-region option, and it **does not** pass the database URL to the platform: you do that by hand in step 5 below.

1. **Get an Aeon API key:** Aeon console → **Usage & Billing → API Keys** → create a key.
2. **Fill these in the environment's `global-values.yaml`** (private repo only):

   ```yaml
   global:
     yugabyte_managed_auth_token: "<aeon-api-key>"
     yugabyte_managed_db_username: "<aeon-admin-user>"
     yugabyte_managed_db_password: "<aeon-admin-password>"
   ```

   Aeon may not accept `yugabyte` as the admin user name (the module's default), so pick another name, e.g. `admin`.
3. **Run the module.** `install.sh` doesn't run it, so apply it by hand from the environment folder:

   ```bash
   cd ~/sunbird-spark-installer/opentofu/azure/test
   source tf.sh
   cd yugabyte-managed && terragrunt apply && cd ..
   ```

   It runs after `create_tf_resources` (it needs the `network` module's outputs). Creating the cluster takes several minutes.

   The `yugabyte-managed` folder only exists in the environment if it was copied from the `benchamarking` branch's `opentofu/azure/template`. Otherwise, copy `opentofu/azure/template/yugabyte-managed/` from that branch into the environment folder first.
4. **Read the database URL (host) from the module's outputs:**

   ```bash
   cd yugabyte-managed
   terragrunt output -raw private_host     # e.g. pse-centralindia.<cluster-id>.azure.yugabyte.cloud
   terragrunt output -raw private_ip       # the private endpoint's IP inside the ed-test VNet
   cd ..
   ```

   `private_host` is the **Aeon host**: use it as `AEON_HOST` in part 7 and as `global.yugabyte.host` in part 8.
5. **Set the host for the platform.** The module doesn't write it anywhere. Put `private_host` into `global.yugabyte_managed.host` in **part 8.1**; that one flag block points every service at it.
6. **Download the CA certificate** from the Aeon console (cluster → **Connect → Download CA Cert**), as in part 4 step 12. The module doesn't fetch it.
7. **Check the private endpoint is approved.** The module creates it as a manual-approval connection. In the Azure portal, open `test-yugabyte-pe` and check **Connection status: Approved**; Aeon approves it automatically because your subscription is allowed. If it stays **Pending**, approve it from the Aeon console (**Network Access → Private Service Endpoint**).

Then continue with part 6 (test the connection), using `private_host`.

---

## Part 6 — Test the connection

From the installer VM:

```bash
nslookup <aeon-host>        # must return the private IP from 5b.8
nc -zv <aeon-host> 5433     # YSQL
nc -zv <aeon-host> 9042     # YCQL
ysqlsh "host=<aeon-host> port=5433 dbname=yugabyte user=<aeon-admin-user> sslmode=verify-full sslrootcert=root.crt" -c "SELECT version();"
```

From inside AKS:

```bash
kubectl -n sunbird run aeon-test --rm -it --restart=Never --image=busybox -- \
  sh -c "nslookup <aeon-host>; nc -zv <aeon-host> 5433; nc -zv <aeon-host> 9042"
```

If `nslookup` returns a public IP or nothing, recheck the zone name, the VNet link (5c.2) and the A record (5c.3).

Install the tools the next part needs on the installer VM: `kubectl`, `az`, `yq`, and `ysqlsh` / `ycqlsh` from the YugabyteDB client package.

---

## Part 7 — Migrate the data

Run on the installer VM. **Downtime starts at 7.2.**

### 7.1 Set the values

```bash
export KUBECONFIG=~/.kube/config && kubectl config use-context ed-test

ENV_DIR=~/sunbird-spark-installer/opentofu/azure/test
SA=edtestace365b8
PRIV=ed-test-private-6b89b2952a
OLD_USER=yugabyte

AEON_HOST="<aeon-host>"                 # Host from part 5a
AEON_USER="<aeon-admin-user>"           # from part 4, step 10
AEON_PASSWORD="<aeon-admin-password>"
AEON_CA=~/yb-migration/root.crt         # from part 4, step 12
```

For another environment, read `SA` and `PRIV` from its `global-cloud-values.yaml`: `yq '.global.cloud_storage_access_key, .global.private_container_name' global-cloud-values.yaml` (`cloud_storage_access_key` holds the storage account **name**).

### 7.2 Stop all apps (downtime starts)

```bash
mkdir -p ~/yb-migration && cd ~/yb-migration
kubectl -n sunbird get deploy -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.replicas}{"\n"}{end}' > replicas.txt
kubectl -n sunbird scale deploy --all --replicas=0
```

### 7.3 Take a fresh backup

```bash
CJ=$(kubectl -n sunbird get cronjob -o name | grep yugabyte-backup)
kubectl -n sunbird create job --from="$CJ" yb-migration-backup
kubectl -n sunbird wait --for=condition=complete job/yb-migration-backup --timeout=2h
```

### 7.4 Download the backup

```bash
cd ~/yb-migration
TS=$(az storage blob list --account-name "$SA" -c "$PRIV" --auth-mode login \
  --prefix yugabyte-backups/ysql/keycloak/ --query "[].name" -o tsv | sort | tail -1 | xargs basename | sed 's/\.sql\.gz$//')
echo "backup timestamp: $TS"

for db in keycloak registry quartz enc-keys kong portal superset sunbird; do
  az storage blob download --account-name "$SA" -c "$PRIV" --auth-mode login \
    -n "yugabyte-backups/ysql/$db/$TS.sql.gz" -f "ysql-$db.sql.gz" -o none
done

az storage blob list --account-name "$SA" -c "$PRIV" --auth-mode login \
  --prefix yugabyte-backups/ycql/ --query "[?contains(name,'$TS')].name" -o tsv |
while read -r blob; do
  ks=$(echo "$blob" | cut -d/ -f3)
  az storage blob download --account-name "$SA" -c "$PRIV" --auth-mode login -n "$blob" -f "ycql-$ks.tar.gz" -o none
  mkdir -p "ycql/$ks" && tar -xzf "ycql-$ks.tar.gz" -C "ycql/$ks"
done
```

The printed timestamp should be from 7.3. If it's older, the backup job didn't finish.

### 7.5 Restore YSQL into Aeon

```bash
export PGHOST="$AEON_HOST" PGPORT=5433 PGUSER="$AEON_USER" PGPASSWORD="$AEON_PASSWORD"
export PGSSLMODE=verify-full PGSSLROOTCERT="$AEON_CA"

for db in keycloak registry quartz enc-keys kong portal superset sunbird; do
  gunzip -c "ysql-$db.sql.gz" | sed '/OWNER TO /d' > "ysql-$db.sql"
  ysqlsh -d yugabyte -f "ysql-$db.sql" > "restore-$db.log" 2>&1
done
```

`OWNER TO` lines are removed because Aeon doesn't let you use the `yugabyte` role. `\restrict` / `\unrestrict` messages in the logs are harmless.

### 7.6 Restore YCQL into Aeon

```bash
export SSL_CERTFILE="$AEON_CA"
YCQL="ycqlsh $AEON_HOST 9042 --ssl -u $AEON_USER -p $AEON_PASSWORD"

cd ~/yb-migration/ycql
for ks in */; do
  ks=${ks%/}; dir=$(dirname "$(find "$ks" -name schema.cql | head -1)")
  $YCQL -f "$dir/schema.cql"
  for csv in "$dir"/*.csv; do
    $YCQL -e "COPY $ks.$(basename "$csv" .csv) FROM '$csv' WITH HEADER=true AND MAXBATCHSIZE=20;"
  done
done
```

The schema keeps its YugabyteDB options (`transactions`, multi-column indexes), which Aeon supports. `janusgraph` is the largest keyspace and takes the longest.

### 7.7 Check the data

```bash
kubectl -n sunbird exec yb-tserver-0 -c yb-tserver -- ysqlsh -h yb-tserver-service -U "$OLD_USER" -d keycloak -tAc "SELECT count(*) FROM user_entity;"
ysqlsh -d keycloak -tAc "SELECT count(*) FROM user_entity;"

kubectl -n sunbird exec yb-tserver-0 -c yb-tserver -- ycqlsh yb-tserver-service -e "SELECT count(*) FROM sunbird.user;"
$YCQL -e "SELECT count(*) FROM sunbird.user;"
```

Each pair of numbers should match.

---

## Part 8 — Switch the platform to Aeon

### 8.1 Turn on the managed flag

In the test environment's `global-values.yaml` (`spark-devops-test/configs/test/global-values.yaml` in the private repo, or `opentofu/azure/test/global-values.yaml` on the installer VM). Real passwords go here, never in this public repo.

```yaml
global:
  use_cassandra_postgres: false
  yugabyte_managed:
    enabled: true
    host: "<aeon-host>"              # Host from part 5a (or private_host from 5d)
    port: 9042
    postgresql_port: 5433
    username: "<aeon-admin-user>"
    password: "<aeon-admin-password>"
```

That's the whole switch. With `yugabyte_managed.enabled: true`:

| What | Effect |
|---|---|
| Every service in edbb, learnbb, knowledgebb, obsrvbb | connects to the managed host, through the shared `sunbird.*` helpers in each bundle's `templates/_database.tpl`: Kong, Keycloak, registry, lern, certregistry, knowlg, sync-tool, Flink jobs, knowledge-mw, player/portal (SQL and forms), superset, keycloak-kids-keys |
| JanusGraph | connects to the managed host (its storage helper follows the same flag) |
| YCQL / YSQL migration jobs | connect to the managed host, logging in with the managed user and password |
| Addons (dial, groups, video-stream-generator, asset-enrichment) | connect to the managed host (`addon.dbHost` / `addon.dbPort` helpers) |
| In-cluster YugabyteDB | **not deployed**: `install.sh` sets `yugabyte.enabled=false` for edbb |
| `yugabyte-backup` | **not deployed**: Aeon has its own backups |

If `enabled` is true but `host` is empty, or `yugabyte_managed` and `use_cassandra_postgres` are both on, the edbb install stops with a clear error.

Also apply the TLS settings from part 1b.

To go back to the in-cluster YugabyteDB, set `enabled: false` and redeploy.

### 8.2 Redeploy

```bash
cd "$ENV_DIR"
./install.sh install_component edbb
./install.sh install_component learnbb
./install.sh install_component knowledgebb
./install.sh install_component obsrvbb
./install.sh install_component additional
```

### 8.3 Start the apps and verify (downtime ends)

```bash
while read -r n r; do kubectl -n sunbird scale deploy "$n" --replicas="$r"; done < ~/yb-migration/replicas.txt
```

Log in to the portal, open existing courses and content, and run `./install.sh run_post_install`.

---

## Rollback

The in-cluster YugabyteDB isn't changed by this procedure. To go back, set `global.yugabyte_managed.enabled: false` in `global-values.yaml` and redeploy the bundles as in 8.2. Data written to Aeon after the switch is not copied back.

Delete the old YugabyteDB volumes only once you're sure you won't roll back.
