# Certificate Verification Fix Runbook

## Problem
All certificates issued on dev cluster failed verification ("Verification Failed" / "Invalid" on portal).

## Root Cause
1. `certificatesign` service signs certs with `hXuG7wVF...` private key
2. Registry had WRONG public key (`1-e36ffe69-...` = testing env's key, not dev's)
3. Cert gets `issuer.kid = 1-e36ffe69-...` (first result from empty registry search)
4. Portal fetches that key → gets 404 (inactive or wrong key) → verification fails

Secondary cause: `CERTIFICATE_PRIVATE_KEY` / `CERTIFICATESIGN_PRIVATE_KEY` keys were missing from `global-values.yaml` in private repo — would cause new keys to be regenerated on next learnbb redeploy, breaking certs again.

---

## Fix Steps

### Step 1: Get actual keys from running pods
```bash
export KUBECONFIG=<dev-kubeconfig>

# Get CERTIFICATESIGN_PUBLIC_KEY (actual key pod uses)
kubectl -n sunbird get configmap certificatesign-env -o jsonpath='{.data.CERTIFICATE_PUBLIC_KEY}'

# Get CERTIFICATESIGN_PRIVATE_KEY
kubectl -n sunbird get configmap certificatesign -o jsonpath='{.data.config\.json}' | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d['issuers']['default']['privateKey'])"
```

### Step 2: Add cert keys to global-values.yaml in private repo
Decrypt, add under `# CERTIFICATE-KEYS` comment, re-encrypt:
```bash
cd configs/dev/
ansible-vault decrypt global-values.yaml --vault-password-file=<vault-pass>
# Add 4 keys (CERTIFICATE_PRIVATE_KEY, CERTIFICATE_PUBLIC_KEY, CERTIFICATESIGN_PRIVATE_KEY, CERTIFICATESIGN_PUBLIC_KEY)
ansible-vault encrypt global-values.yaml --vault-password-file=<vault-pass>
git add global-values.yaml && git commit && git push
```

Key format:
- `CERTIFICATE_PRIVATE/PUBLIC_KEY`: single `\n` escaping
- `CERTIFICATESIGN_PRIVATE/PUBLIC_KEY`: double `\\n` escaping

### Step 3: Fix registry — remove wrong keys, register correct key

```bash
export KUBECONFIG=<dev-kubeconfig>

# Hard-delete old testing key from OpenSearch (soft-delete not enough — still shows in search)
kubectl -n sunbird exec deployment/knowledge-mw -- curl -s -X DELETE \
  'http://opensearch-cluster-master:9200/publickey/_doc/e36ffe69-c765-4011-8c73-fc1f3b6025f0'

# Hard-delete any other wrong keys the same way
kubectl -n sunbird exec deployment/knowledge-mw -- curl -s -X DELETE \
  'http://opensearch-cluster-master:9200/publickey/_doc/<wrong-osid-without-1- prefix>'

# Register correct CERTIFICATESIGN_PUBLIC_KEY
CERTSIGN_PUBKEY=$(kubectl -n sunbird get configmap certificatesign-env -o jsonpath='{.data.CERTIFICATE_PUBLIC_KEY}')
echo "$CERTSIGN_PUBKEY" | kubectl -n sunbird exec -i deployment/knowledge-mw -- python3 -c "
import sys, json, urllib.request
key = sys.stdin.read().strip()
payload = json.dumps({'value': key}).encode()
req = urllib.request.Request(
    'http://registry-service:8081/api/v1/PublicKey',
    data=payload,
    headers={'Content-Type': 'application/json'},
    method='POST'
)
with urllib.request.urlopen(req) as r:
    print(r.read().decode())
"
```

Verify only correct key in registry:
```bash
kubectl -n sunbird exec deployment/knowledge-mw -- curl -s -X POST \
  'http://registry-service:8081/api/v1/PublicKey/search' \
  -H 'Content-Type: application/json' \
  -d '{"filters": {}}' | python3 -c "
import sys,json
for k in json.load(sys.stdin):
    print('osid:', k['osid'])
"
# Should show exactly ONE osid — the new correct one
```

### Step 4: Restart cert pods
```bash
kubectl rollout restart deployment/certificatesign deployment/cert deployment/certificateapi -n sunbird
kubectl rollout status deployment/certificatesign deployment/cert deployment/certificateapi -n sunbird --timeout=120s
```

### Step 5: Verify fix — check logs on next cert issue
```bash
kubectl logs deployment/certificatesign -n sunbird --since=5m | grep "publicKey\|Signed cert"
# Should show: publicKey: [ '<new-osid>' ]
```

---

## Re-issue Old Failing Certs

Old certs have wrong kid baked in permanently. Must re-issue via **Kafka directly**.

> **Why not lern-service API?** `POST /v1/course/batch/cert/issue` with `reIssue: true` — lern-service publishes Kafka message with `reIssue: false` (bug). Flink finds user already has cert → skips. Must publish to Kafka directly with `reIssue: true`.

### Step 1: Get all failing certs from registry

Use `limit: 200` (not 100 — there may be more than 100). The `training.batchId` field in the cert contains the batchId directly.

```bash
NEW_KID="<new-correct-osid>"   # from Step 3 above

kubectl -n sunbird exec deployment/knowledge-mw -- curl -s -X POST \
  'http://registry-service:8081/api/v1/TrainingCertificate/search' \
  -H 'Content-Type: application/json' \
  -d '{"filters": {}, "limit": 200}' | python3 -c "
import sys,json
d=json.load(sys.stdin)
certs = d if isinstance(d,list) else d.get('result',{}).get('TrainingCertificate',[])
failing=[]
for c in certs:
    kid = c.get('issuer',{}).get('kid','')
    if kid != '$NEW_KID':
        failing.append({
            'userId': c.get('recipient',{}).get('id'),
            'courseId': c.get('training',{}).get('id'),
            'batchId': c.get('training',{}).get('batchId'),   # batchId IS in training object
            'oldId': c.get('osid')
        })
print(f'Failing: {len(failing)}')
import json as j; print(j.dumps(failing))
"
```

To filter by specific user:
```bash
# Replace USER_ID with actual userId
... | python3 -c "... if uid == 'USER_ID' and kid != NEW_KID ..."
```

### Step 2: Publish re-issue to Kafka directly

```python
import time, json, subprocess

NEW_KID = "<new-correct-osid>"
KAFKA_TOPIC = "<env>.issue.certificate.request"  # e.g. test.issue.certificate.request

# failing_certs = list from Step 1
for i, c in enumerate(failing_certs):
    ts = int(time.time()*1000) + i
    msg = json.dumps({
        'eid': 'BE_JOB_REQUEST',
        'ets': ts,
        'mid': f'LP.{ts}.reissue-{i}',
        'actor': {'id': 'Course Certificate Generator', 'type': 'System'},
        'context': {'pdata': {'ver': '1.0', 'id': 'org.sunbird.platform'}},
        'object': {'id': f"{c['batchId']}_{c['courseId']}", 'type': 'CourseCertificateGeneration'},
        'edata': {
            'userIds': [c['userId']],        # specific user
            'action': 'issue-certificate',
            'iteration': 1,
            'trigger': 'auto-issue',
            'batchId': c['batchId'],
            'reIssue': True,                 # MUST be True — lern-service sets this False (bug)
            'courseId': c['courseId'],
            'oldId': c['oldId']              # existing cert osid — required for update
        }
    })
    subprocess.run([
        'kubectl','-n','sunbird','exec','kafka-controller-0','--','bash','-c',
        f"echo '{msg}' | kafka-console-producer.sh --bootstrap-server kafka:9092 --topic {KAFKA_TOPIC}"
    ])
    time.sleep(0.2)  # small delay to avoid flooding
```

### Step 3: Verify Flink processed certs
```bash
# Count certs issued by Flink
kubectl logs deployment/collection-certificate-generator-taskmanager -n sunbird --since=10m \
  | grep "issued certificates in user-enrollment" | wc -l

# After processing, user re-downloads cert from portal → Profile → Certificates
# Old downloaded PDFs are permanently broken — must re-download fresh from portal
```

### Step 4: Verify specific cert was re-issued
```bash
kubectl -n sunbird exec deployment/knowledge-mw -- curl -s -X POST \
  'http://registry-service:8081/api/v1/TrainingCertificate/search' \
  -H 'Content-Type: application/json' \
  -d '{"filters": {}, "limit": 200}' | python3 -c "
import sys,json
NEW_KID='<new-osid>'
d=json.load(sys.stdin)
certs = d if isinstance(d,list) else d.get('result',{}).get('TrainingCertificate',[])
still_failing = [c for c in certs if c.get('issuer',{}).get('kid','') != NEW_KID]
print(f'Still failing: {len(still_failing)}')
"
```

---

## Key Notes

### Why soft-delete is not enough for registry
Sunbird RC soft-delete marks entity as `INACTIVE` in YugabyteDB but **still indexes it in OpenSearch**. The `certificatesign` service does empty registry search (`filters: {}`) and picks FIRST result. If old inactive key is still in OpenSearch, it gets picked.

**Fix:** Always hard-delete from OpenSearch index directly:
```bash
# osid format in ES: remove the "1-" prefix
curl -X DELETE 'http://opensearch-cluster-master:9200/publickey/_doc/<osid-without-1-prefix>'
```

### Why lern-service reIssue:true doesn't work
`/v1/course/batch/cert/issue` API with `reIssue: true` body — lern-service publishes Kafka message with `reIssue: false`. Bug in lern-service. Must publish to Kafka directly.

### Certificate key lifecycle
- `certificate_keys()` in `install.sh` generates keys ONLY when `CERTIFICATE_PRIVATE_KEY` not in `global-values.yaml` AND `certkey.pem`/`certpubkey.pem` don't exist
- Keys MUST be in private repo `global-values.yaml` or they'll be regenerated → new keys → registry mismatch → certs fail again
- Workflow now auto-commits keys after learnbb deploy (see `sunbird-spark-platform.yaml`)

### Finding which kid certificatesign uses
```bash
kubectl -n sunbird get configmap certificatesign -o jsonpath='{.data.config\.json}' | python3 -m json.tool | grep publicKey
```
This public key must be registered in registry. The osid returned becomes the kid in all new certs.

---

## Verification Checklist
- [ ] Only 1 key in registry search (`/api/v1/PublicKey/search`)
- [ ] That key's value matches `certificatesign` configmap `config.json` publicKey
- [ ] `certificatesign` logs show new osid in `publicKey: [...]` after cert sign
- [ ] New cert downloaded from portal passes verification
- [ ] `CERTIFICATE_PRIVATE_KEY` present in `global-values.yaml` in private repo
