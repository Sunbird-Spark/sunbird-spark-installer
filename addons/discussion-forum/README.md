# Discussion Forum Addon

Decentralized Kong API onboarding for the Discussion Forum addon, following Approach 4 (`--managed-by` Ownership Tags) from the Kong API decoupling strategy.

## Overview

This addon deploys:
1. **discussion-forum-apis** - Kong API onboarding chart (31 APIs)
2. **discussionmw** - Discussion Middleware service
3. **nodebb** - NodeBB forum platform
4. **groups** - Groups service

The addon-owned APIs are **completely isolated** from core APIs. They are tagged with `managed-by:discussion-forum` in Kong, which means:
- Core upgrades can never delete discussion APIs
- Addon upgrades only affect discussion APIs
- Both can be upgraded independently

## Directory Structure

```
addons/discussion-forum/
├── script/
│   └── addon.sh                      # Deployment orchestration
├── helmcharts/
│   ├── discussion-forum-apis/         # Kong API onboarding chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml                # managed_by: discussion-forum
│   │   ├── configs/
│   │   │   └── kong-apis.yaml         # 31 APIs (7 groups + 24 discussion)
│   │   └── templates/
│   │       ├── configmap.yaml
│   │       ├── job.yaml               # --managed-by=discussion-forum
│   │       └── _helpers.tpl
│   ├── discussionmw/                  # Discussion Middleware service
│   ├── nodebb/                        # NodeBB forum platform
│   └── groups/                        # Groups service
└── README.md
```

## Deployment

### Prerequisites
```bash
export ENV_NAME=<your-environment>     # e.g., demo, staging, prod
export CLOUD_PROVIDER=azure            # or gcp
```

### Install
```bash
cd addons/discussion-forum
./script/addon.sh install [azure|gcp]
```

Deployment order:
1. `discussion-forum-apis` - registers 31 Kong APIs (tagged managed-by:discussion-forum)
2. `discussionmw` - discussion middleware service
3. `nodebb` - nodebb forum
4. `groups` - groups service

### Uninstall
```bash
./script/addon.sh uninstall [azure|gcp]
```

## Kong API Isolation Strategy

### The Problem (Solved)
Old approach: All 500+ APIs (core + addons) in one 9,073-line `kong-apis.yaml`
- Every core upgrade deleted addon APIs
- Addons had no autonomy
- File was unmaintainable

### The Solution: Ownership Tags
Each chart tags its Kong services:
- **Core**: `managed-by:core` (470 APIs)
- **Addon**: `managed-by:discussion-forum` (31 APIs)

Kong sync script now:
1. Fetches ONLY services with its tag when deleting
2. Stamps the tag on every service it creates
3. Never touches other charts' services

### Result: Perfect Isolation
```
Core Upgrade:
  → Kong API: GET /services?tags=managed-by:core
  → 31 addon services INVISIBLE
  → Sync succeeds safely ✓

Addon Upgrade:
  → Kong API: GET /services?tags=managed-by:discussion-forum
  → 470 core services INVISIBLE
  → Sync succeeds safely ✓
```

## API Coverage

### Groups Service (7 APIs)
- createGroup, updateGroup, listGroup, readGroup, deleteGroup
- updateGroupMembership
- groupActivityAgg

### Discussion Middleware (24 APIs)
**Read:** getDiscussionTagsList, getDiscussionCategories, getDiscussionNotificationsList, getUserDetailsOfDiscussion, getCategoryDetailsOfDiscussion, getUnreadTopicsOfDiscussion, getRecentTopicsOfDiscussion, getPopularTopicsOfDiscussion, getTopTopicsOfDiscussion, getTopicsOfDiscussionById, getTotalUnreadTopicsOfDiscussion, getTopicsOfDiscussionByTeaserId, getTopicsPaginationByIdOfDiscussion, getGroupsListOfDiscussion, getRecentPostsByDateOfDiscussions, getUserDetailsByUsername, getForumIdOfDiscussion

**Write:** createTopicOfDiscussions, createCategoryOfDiscussion, createGroupsOfDiscussion, createNewPostOfDiscussion, createNewUserOfDiscussion, addForumOfDiscussion, copyPrivilegesFromParentCategory

All with JWT auth, CORS, rate-limiting, and ACL.

## Documentation

See **[KONG_API_DECOUPLING_PLAN.md](../../helmcharts/edbb/charts/kong-apis/KONG_API_DECOUPLING_PLAN.md)** for:
- Problem statement & motivation
- All 4 approaches evaluated
- Implementation details
- Migration safety
