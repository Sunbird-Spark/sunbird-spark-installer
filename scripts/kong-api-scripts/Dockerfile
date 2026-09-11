FROM python:3.14-slim@sha256:cad9a2c871761c413caa6fdd6441c783451e740a48aaeba60ae62a8b53525ef6
COPY common.py kong_apis.py kong_consumers.py __init__.py kong_api_csv_to_yaml.py kong_apis_report.py kong_yaml_to_json.py requirements.txt /
RUN pip install --require-hashes --only-binary :all: -r /requirements.txt && \
    useradd --uid 1001 --home-dir /home/kongapi kongapi
USER 1001

