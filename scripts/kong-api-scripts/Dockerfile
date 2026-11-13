FROM python:3.15-slim@sha256:65a65fc7b30b06cb6df4930fd4650697cb23f4c2698ab81fc87e4b031bc36928
COPY common.py kong_apis.py kong_consumers.py __init__.py kong_api_csv_to_yaml.py kong_apis_report.py kong_yaml_to_json.py requirements.txt /
RUN pip install --require-hashes --only-binary :all: -r /requirements.txt && \
    useradd --uid 1001 --home-dir /home/kongapi kongapi
USER 1001

