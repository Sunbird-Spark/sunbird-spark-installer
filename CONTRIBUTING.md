<!-- omit in toc -->
# Spark Installer Contributing Guide

First off, thanks for taking the time to contribute! ❤️

This repository is the **Sunbird Spark installer** — the infrastructure and deployment layer. It provisions a Kubernetes cluster and installs the full Spark stack on Azure, AWS or GCP using **OpenTofu** and **Terragrunt** for infrastructure, **Helm** charts for the services, and shell scripts for the glue.

There is no application to run here. A contribution is a change to infrastructure modules, charts, scripts, Dockerfiles or workflows — and the way you verify it is different from a normal code repository. That shapes most of what's below.

The general contribution process is the same across the [Sunbird Spark organisation](https://github.com/Sunbird-Spark). Everything here is specific to this repository.

<!-- omit in toc -->
## Table of Contents

<!-- - [Code of Conduct](#code-of-conduct) -->
- [I Have a Question](#i-have-a-question)
- [I Want To Contribute](#i-want-to-contribute)
  - [Before You Start](#before-you-start)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Enhancements](#suggesting-enhancements)
  - [Your First Code Contribution](#your-first-code-contribution)
  - [Improving The Documentation](#improving-the-documentation)
- [Contribution Standards](#contribution-standards)
  - [Using AI Tools](#using-ai-tools)
- [Styleguides](#styleguides)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [What Happens After You Submit](#what-happens-after-you-submit)

<!-- ## Code of Conduct

This project and everyone participating in it is governed by the [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold it. Report unacceptable behaviour to TODO_CONTACT_EMAIL.

Before uncommenting: add CODE_OF_CONDUCT.md to this repository and replace TODO_CONTACT_EMAIL. -->

## I Have a Question

Check the [README](README.md) first — it covers infrastructure sizing, prerequisites, required CLI tools and the deployment paths. Deeper material lives in [INFRA_DETAILS.md](INFRA_DETAILS.md), [private-repo-setup/README.md](private-repo-setup/README.md) and [opentofu/azure/README.md](opentofu/azure/README.md). Then search existing [Issues](https://github.com/Sunbird-Spark/sunbird-spark-installer/issues) and [Discussions](https://github.com/orgs/Sunbird-Spark/discussions).

If you still need help, open a thread in [Discussions](https://github.com/orgs/Sunbird-Spark/discussions). Say which cloud provider you're on, your OpenTofu and Terragrunt versions, and whether the cluster is private with VPN or Bastion access.

## I Want To Contribute

> When contributing to this project, you must agree that you have authored 100% of the content, that you have the necessary rights to the content, and that the content you contribute may be provided under the project licence.

### Before You Start

Create a copy of, and fill in, the [**Sunbird Contribution Checklist**](https://docs.google.com/spreadsheets/d/1k0x3NEBvQAAEAm6WZzG3RqmzNnX9U8ywABjc4pKfttg/edit?usp=sharing). Share the filled-in copy with the maintainer so you're aligned before you write anything.

**When it's needed:** for changes to OpenTofu modules, Helm charts, scripts, Dockerfiles or workflows. Small documentation edits and typo fixes don't need one — open the PR and describe what you changed.

**This one matters more here than elsewhere.** A change to this repository can break deployments for every adopter, and mistakes surface at install time on someone else's cloud account rather than in a test run. Agree the approach before you build.

### Reporting Bugs

Before reporting, check [INFRA_DETAILS.md](INFRA_DETAILS.md) and the provider READMEs, and search the [issue tracker](https://github.com/Sunbird-Spark/sunbird-spark-installer/issues?q=label%3Abug). Many install failures come from prerequisites — a missing SSL fullchain, unset OAuth or ReCaptcha credentials, or a CLI tool at the wrong version.

> Never report security issues publicly. Follow [SECURITY.md](SECURITY.md) — use private vulnerability reporting. Maintainers acknowledge within 3 business days.

[Open a bug report](https://github.com/Sunbird-Spark/sunbird-spark-installer/issues/new/choose). Include your cloud provider, the environment name, your OpenTofu and Terragrunt versions, which step failed, and the error output. **Redact subscription IDs, account numbers, domains, certificates and anything from `global-values.yaml` before pasting logs.**

### Suggesting Enhancements

Bear in mind what this installer is for: a reproducible, minimal-resource install of the full Spark stack that any adopter can run on their own cloud account. Changes that help one deployment at the cost of that portability are unlikely to land.

[Open a feature request](https://github.com/Sunbird-Spark/sunbird-spark-installer/issues/new/choose) describing the problem it solves, which providers it affects, and what it costs in cluster resources. **Agree the approach on the issue before writing significant code.**

### Your First Code Contribution

**1. Pick something and claim it.** Filter issues by `good first issue` and `help wanted`, then comment to say you're taking it.

**2. Fork, clone and set up your tools.**

```bash
# Fork on GitHub, then:
git clone https://github.com/<your-username>/sunbird-spark-installer.git
cd sunbird-spark-installer
git remote add upstream https://github.com/Sunbird-Spark/sunbird-spark-installer.git
```

You'll need the CLI tools listed in the README — `jq`, `yq`, `rclone`, OpenTofu, Terragrunt, `kubectl`, `helm`, Python 3 with PyJWT, and the Postman CLI. The installer is verified against **OpenTofu 1.11.4** and **Terragrunt 0.77.5**; CI uses OpenTofu 1.11.4, so match it.

For running the static checks locally you'll also want `shellcheck`, `hadolint` and `actionlint`.

**There is nothing to "run locally" in the usual sense.** A full deployment provisions a real cluster on a real cloud account and costs real money. So verification comes in two layers:

- **Static checks** catch most mistakes and cost nothing. Run them on every change — see Code sanity below.
- **A real deployment** is the only way to prove an infrastructure change works. If your change affects provisioning, charts or the install flow, deploy it to your own account in a throwaway environment before opening the PR, and say so in the PR description. If you can't, say that too — a maintainer can arrange verification, but they need to know.

**3. Branch.** Branch from the latest release branch — `v1.x.x`, the development branch for the next release; check the branch list for the current one. Don't branch from `main`, which holds the released version. Keep the change to one logical unit.

**4. Code sanity.** Run what CI runs, before you push:

```bash
# Workflows
actionlint

# Shell scripts — errors only; skip Helm-templated scripts, which aren't valid shell as committed
git ls-files '*.sh' | xargs grep -L '{{' | xargs shellcheck -S error -f gcc

# Dockerfiles
hadolint --failure-threshold error $(git ls-files '*Dockerfile*')

# OpenTofu — formatting, then validate each module
tofu fmt -check -recursive -list=true opentofu
for dir in opentofu/azure/modules/*/ opentofu/gcp/modules/*/; do
  (cd "$dir" && tofu init -backend=false -input=false >/dev/null && tofu validate -no-color)
done

# Helm charts
helm lint helmcharts/<chart> -f helmcharts/<chart>/values.yaml -f helmcharts/images.yaml \
  -f helmcharts/global-resources.yaml -f opentofu/azure/template/global-values.yaml

# For learnbb, knowledgebb, obsrvbb and additional, add their ed-values.yaml
# immediately after the chart's own values.yaml — CI does, and without it you
# get warnings CI never sees:
helm lint helmcharts/<chart> -f helmcharts/<chart>/values.yaml \
  -f helmcharts/<chart>/ed-values.yaml -f helmcharts/images.yaml \
  -f helmcharts/global-resources.yaml -f opentofu/azure/template/global-values.yaml
```

`actionlint`, `shellcheck`, `hadolint` and `tofu validate` **will fail the build**. `tofu fmt` and `helm lint` are advisory today because neither is clean across the repository — don't let your change add to that, and if you're touching a module or chart, leaving it cleaner than you found it is welcome.

Also:

- **Keep workflow actions pinned to a commit SHA with a version comment.** This repository is scored by [OpenSSF Scorecard](https://scorecard.dev/viewer/?uri=github.com/Sunbird-Spark/sunbird-spark-installer); replacing a SHA with a tag lowers that score and weakens the supply chain.
- **Keep workflow permissions minimal.** The default is `contents: read`; grant more only in the job that needs it.
- **Keep base images digest-pinned** in the Dockerfiles under `scripts/`. Dependabot maintains both these and the action pins.
- **Never commit credentials** — cloud keys, SSL private keys, SendGrid or MSG91 tokens, OAuth or ReCaptcha secrets, Ansible Vault passwords, `kubeconfig` files or anything from a filled-in `global-values.yaml`.
- **Mind the resource budget.** The stack is sized to fit two 16 vCPU / 64 GB nodes with all addons. If your change raises requests or limits, say by how much in the PR, and update [INFRA_DETAILS.md](INFRA_DETAILS.md).

**Before opening the PR:**

- [ ] Opened against the latest release branch, not `main`
- [ ] Issue linked, and you commented on it to say you're taking it
- [ ] Static checks pass locally — actionlint, shellcheck, hadolint, `tofu validate`
- [ ] Deployed and verified on your own cloud account, or stated in the PR that you couldn't
- [ ] Documentation updated — the README, `INFRA_DETAILS.md` or the provider READMEs, wherever your change made them wrong
- [ ] No credentials, certificates, kubeconfigs or account identifiers in the diff
- [ ] **If you changed the Keycloak login theme under `scripts/keycloak-21.1.2/themes/sunbird/login/`, you bumped `styles=css/login.css?v=…` in `theme.properties`** — otherwise browsers serve the cached stylesheet and your change won't appear
- [ ] Your filled-in copy of the Sunbird Contribution Checklist is complete, with details rather than just ticks, and ready to attach

### Improving The Documentation

Documentation fixes are real contributions and an ideal first one. This repository leans on its docs more than most — there's no application to explore, so the README is the product for anyone installing Spark for the first time.

- **Where:** `README.md` for the overview and prerequisites; `INFRA_DETAILS.md` for per-component resources; `private-repo-setup/README.md` and `opentofu/azure/README.md` for the deployment paths.
- **Voice:** plain, direct, active. Write for a competent operator who has never deployed Spark before.
- **Be exact about versions and commands.** A wrong CLI version here costs someone an afternoon and possibly a half-provisioned cluster.
- **Accessibility:** descriptive link text, alt text on images, real heading levels.
- Update the docs in the same change that made them wrong.

## Contribution Standards

Spark is a digital public good, deployed as national-scale infrastructure. That shapes what good work means here:

1. **Serve the public-good mission** — this installer exists so any adopter can stand up Spark on their own terms. Changes should widen that, not narrow it.
2. **Uphold platform independence** — Azure is the most developed path, but AWS and GCP are supported and must stay supported. Don't add anything that only works on one provider without a documented reason.
3. **Protect privacy and secrets as policy, not just code** — credentials belong in Ansible Vault or your cloud's secret store, never in the repository.
4. **Do no harm by design** — an adopter running this may have limited budget and limited operations staff. Resource increases and added complexity have a real cost to them.
5. **Write for people outside your team** — someone will run this without being able to ask you a question.
6. **Treat documentation as part of the contribution.**
7. **Follow the repository for mechanics** — the README and provider READMEs carry the detail.

### Using AI Tools

Welcome, with conditions:

- **Understand what you submit.** Generated infrastructure code is particularly risky — it looks plausible and fails at provisioning time on someone else's account. If you can't explain it in review, don't open the PR.
- **Attribute it.** Add `Assisted-by: <tool name>` for substantially AI-generated code — not `Co-authored-by:`, which implies a human contributor with authorship rights.
- **Licence hygiene applies.** Output must comply with the provider's terms, infringe nobody's IP, and must not include code under licences incompatible with MIT.
- **Documentation is still required**, and so is saying what you actually verified.

## Styleguides

**Branches:** `<type>/<short-description>` — `feat/velero-backup-schedule`, `fix/kong-cert-renewal`, `docs/gcp-prereqs`.

**Commits:** [Conventional Commits](https://www.conventionalcommits.org/) — `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`, `perf:`.

```bash
git fetch upstream
git checkout -b fix/kong-cert-renewal upstream/v1.1.1   # use the current development branch
git commit -m "fix: renew Kong certificate before expiry check"
```

Keep commits small and atomic, and explain **why**, not just what.

## Submitting a Pull Request

Push your branch and open the PR against the latest `v1.x.x` development branch of `Sunbird-Spark/sunbird-spark-installer` — check the repository for the current one. GitHub defaults the base branch to `main`, so you will need to change it.

The pull request template asks for what changed, why, how you verified it, and anything a reviewer should look at closely. Be specific about verification: which provider, which environment, whether you deployed or only ran static checks. Tag the reviewer or repo owner, and link the GitHub issue and the Jira ticket if applicable.

If you touched authentication, Keycloak, Kong, certificates, secret handling or anything that changes what is exposed publicly, say so and ask for a security-focused review.

## What Happens After You Submit

**1. Automated checks.** [CI](.github/workflows/ci.yml) runs on every PR to `main` or a `v*` branch, and touches no cloud account or cluster. Blocking: `actionlint`, `shellcheck`, `hadolint` and OpenTofu `validate` across every Azure and GCP module. Advisory: `tofu fmt -check` and `helm lint`, which report without failing. [OpenSSF Scorecard](.github/workflows/scorecard.yml) also runs. Fix anything red before asking for review.

**2. Triage.** A maintainer labels the PR and assigns a reviewer. If you haven't heard anything within a week, nudge on the PR or in [Discussions](https://github.com/orgs/Sunbird-Spark/discussions) — a reminder is welcome, not annoying.

**3. Review.** Expect comments, and expect a few rounds. Infrastructure changes usually attract more questions than application code, because the blast radius is larger. Push follow-up commits to the same branch rather than opening a replacement PR, and reply to each comment. If the branch falls behind, `git fetch upstream && git rebase upstream/v1.1.1`.

**4. Approval and merge.** At least one maintainer approval is required, with all comments resolved and CI green. A maintainer merges — contributors don't merge their own PRs.

**After merge.** Your change sits on the `v1.x.x` development branch. When that version is released, the branch is merged into `main`, which becomes the current released version, and a new development branch opens for the next one. Container images for the utilities under `scripts/` are built and pushed when a `spark-v*` tag is created.

> [!NOTE]
> **If your PR is closed without merging,** it's usually scope, direction, or inactivity. The maintainer should say which — ask if it isn't clear.

<!-- omit in toc -->
## Licensing

This repository is licensed under MIT, in line with the DPG code licence. By contributing, you agree your contribution is licensed under the repository's [LICENSE](LICENSE).