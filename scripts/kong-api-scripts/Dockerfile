ARG DHI_IMAGE_DEV=dhi.io/python:3.11-dev
ARG DHI_IMAGE_RUNTIME=dhi.io/python:3.11

FROM ${DHI_IMAGE_DEV} AS build
COPY common.py kong_apis.py kong_consumers.py __init__.py kong_api_csv_to_yaml.py kong_apis_report.py kong_yaml_to_json.py requirements.txt /
RUN pip install -r /requirements.txt

FROM ${DHI_IMAGE_RUNTIME}
COPY --from=build /usr/lib/python3.11/site-packages /usr/lib/python3.11/site-packages
COPY --from=build /common.py /kong_apis.py /kong_consumers.py /__init__.py /kong_api_csv_to_yaml.py /kong_apis_report.py /kong_yaml_to_json.py /
