FROM python:3.11-slim@sha256:9534e5a8e315485d4061ed659af0fd78a284c015f9b73661b41d6bab25604534
COPY common.py kong_apis.py kong_consumers.py __init__.py kong_api_csv_to_yaml.py kong_apis_report.py kong_yaml_to_json.py requirements.txt /
RUN pip install --require-hashes --only-binary :all: -r /requirements.txt && \
    useradd --uid 1001 --home-dir /home/kongapi kongapi
USER 1001

