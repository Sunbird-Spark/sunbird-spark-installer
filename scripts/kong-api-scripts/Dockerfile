ARG DHI_IMAGE_DEV=dhi.io/python:3.11-dev
ARG DHI_IMAGE_RUNTIME=dhi.io/python:3.11

FROM ${DHI_IMAGE_DEV} AS build
COPY common.py kong_apis.py kong_consumers.py __init__.py kong_api_csv_to_yaml.py kong_apis_report.py kong_yaml_to_json.py requirements.txt /
RUN pip install --only-binary :all: -r /requirements.txt && \
    useradd --uid 1001 --home-dir /home/kongapi kongapi
USER 1001

