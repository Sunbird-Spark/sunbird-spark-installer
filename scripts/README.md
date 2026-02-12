# Scripts Directory

## Workflow
1. **Changes**: Modify any script or subdirectory within this folder.
2. **GitHub Action**: On push, a workflow automatically builds and pushes the updated Docker image to [GitHub Packages](https://github.com/orgs/Sunbird-Spark/packages).
3. **Manual Update**: After the action finishes, grab the new image tag and update it in `helmcharts/images.yaml`.

### Example
```yaml
  kong_consumers: &kong_consumers
    repository: "ghcr.io/sunbird-spark/kong-api-scripts"
    tag: "develop_499032f"
```
