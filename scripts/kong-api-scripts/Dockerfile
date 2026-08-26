FROM python:3.11-slim
COPY common.py kong_apis.py kong_consumers.py __init__.py kong_api_csv_to_yaml.py kong_apis_report.py kong_yaml_to_json.py requirements.txt /
RUN pip install --only-binary :all: -r /requirements.txt

RUN useradd --uid 1001 --home-dir /home/kongapi kongapi
USER 1001

