CREATE TABLE IF NOT EXISTS standard_reports_meta (
    report_id         VARCHAR(100)  NOT NULL,
    title             VARCHAR(255)  NOT NULL,
    description       TEXT,
    domain            VARCHAR(50)   NOT NULL,
    data_source       VARCHAR(50)   NOT NULL,
    query_template    TEXT          NOT NULL,
    supported_filters JSONB         NOT NULL DEFAULT '[]'::JSONB,
    enabled           BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMP     NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMP     NOT NULL DEFAULT NOW(),
    aggregation_spec  JSONB,
    PRIMARY KEY (report_id)
);

-- ============================================================
-- Report: content-status-summary
-- Data Source: SEARCHSERVICE
-- ============================================================
--
-- Content count grouped by status, primaryCategory and createdBy.

INSERT INTO standard_reports_meta (
    report_id,
    title,
    description,
    domain,
    data_source,
    query_template,
    supported_filters,
    enabled,
    aggregation_spec
) VALUES (
    'content-status-summary',
    'Content Status Summary',
    'Content count grouped by status, primaryCategory and createdBy',
    'content',
    'SEARCHSERVICE',
    '{
      "request": {
        "filters": {
          {{#createdFor}}"createdFor": ["{{createdFor}}"],
          {{/createdFor}}"status": ["Draft", "Review", "Live", "Retired"],
          "primaryCategory": [
            "Course Assessment",
            "eTextbook",
            "Explanation Content",
            "Learning Resource",
            "Practice Question Set",
            "Teacher Resource",
            "Exam Question",
            "Content Playlist",
            "Course",
            "Digital Textbook",
            "Question paper"
          ]
        },
        "limit": 0,
        "facets": ["status", "primaryCategory", "createdBy"]
      }
    }',
    '["createdFor"]',
    TRUE,
    NULL
) ON CONFLICT (report_id) DO NOTHING;

-- ============================================================
-- Report: course-assessment-summary
-- Data Source: YUGABYTE_CQL_AGG
-- Keyspace: sunbird_courses
-- Note: No index required. course_id is the partition key; batch_id is the first clustering column.
-- ============================================================
--
-- Per-user assessment summary for a course and batch.

INSERT INTO standard_reports_meta (
    report_id,
    title,
    description,
    domain,
    data_source,
    query_template,
    supported_filters,
    enabled,
    aggregation_spec
) VALUES (
    'course-assessment-summary',
    'Course Assessment Summary',
    'Per-user assessment summary for a course and batch',
    'consumption',
    'YUGABYTE_CQL_AGG',
    'SELECT user_id, course_id, batch_id, total_score, total_max_score, last_attempted_on
  FROM sunbird_courses.assessment_aggregator
  WHERE course_id = {{courseid}}
  {{#batchid}}AND batch_id = {{batchid}}{{/batchid}}',
    '["courseid", "batchid"]',
    TRUE,
    '{
      "groupBy": ["user_id"],
      "aggregations": [
        {
          "type": "SUM",
          "sourceField": "total_score",
          "outputField": "total_score"
        },
        {
          "type": "SUM",
          "sourceField": "total_max_score",
          "outputField": "total_max_score"
        },
        {
          "type": "SUM",
          "sourceField": "attempt_count",
          "outputField": "attempt_count"
        },
        {
          "type": "COUNT_ALL",
          "sourceField": "content_id",
          "outputField": "content_count"
        },
        {
          "type": "MAX",
          "sourceField": "last_attempted_on",
          "outputField": "last_attempted_on"
        }
      ],
      "preAggregation": {
        "groupBy": ["user_id", "content_id"],
        "selectBy": {
          "field": "total_score",
          "order": "MAX"
        },
        "aggregations": [
          {
            "type": "COUNT_ALL",
            "sourceField": "attempt_id",
            "outputField": "attempt_count"
          }
        ]
      }
    }'
) ON CONFLICT (report_id) DO NOTHING;

-- ============================================================
-- Report: course-batch-enrolments
-- Data Source: YUGABYTE_CQL
-- Keyspace: sunbird_courses
-- ============================================================
--
-- User enrolments for a course with completion and status info.

INSERT INTO standard_reports_meta (
    report_id,
    title,
    description,
    domain,
    data_source,
    query_template,
    supported_filters,
    enabled,
    aggregation_spec
) VALUES (
    'course-batch-enrolments',
    'Course Enrolments',
    'User enrolments for a course with completion and status info',
    'consumption',
    'YUGABYTE_CQL',
    'SELECT userid, completionpercentage, status, enrolled_date, datetime, issued_certificates
  FROM sunbird_courses.user_enrolments
  WHERE courseid = {{courseid}}
  {{#batchid}}AND batchid = {{batchid}}{{/batchid}}',
    '["courseid", "batchid"]',
    TRUE,
    NULL
) ON CONFLICT (report_id) DO NOTHING;

-- ============================================================
-- Report: org-course-enrolment-summary
-- Data Source: YUGABYTE_CQL_AGG
-- Keyspace: sunbird_courses
-- ============================================================
--
-- Enrolment, completion, and certificate counts per course.

INSERT INTO standard_reports_meta (
    report_id,
    title,
    description,
    domain,
    data_source,
    query_template,
    supported_filters,
    enabled,
    aggregation_spec
) VALUES (
    'org-course-enrolment-summary',
    'Course Batch Enrolment Summary',
    'Enrolment, completion, and certificate counts per course',
    'courses',
    'YUGABYTE_CQL_AGG',
    'SELECT courseid, userid, batchid, status, issued_certificates
  FROM sunbird_courses.user_enrolments
  WHERE courseid IN ({{courseids}})',
    '["courseids"]',
    TRUE,
    '{
      "groupBy": ["courseid"],
      "aggregations": [
        {
          "type": "COUNT_ALL",
          "sourceField": "",
          "outputField": "total_enrolled"
        },
        {
          "type": "COUNT_IF",
          "sourceField": "status",
          "outputField": "total_completed",
          "eq": 2
        },
        {
          "type": "COUNT_IF",
          "sourceField": "issued_certificates",
          "outputField": "certificates_issued",
          "nonEmpty": true
        }
      ]
    }'
) ON CONFLICT (report_id) DO NOTHING;

-- ============================================================
-- Report: user-assessment-summary
-- Data Source: YUGABYTE_CQL
-- Keyspace: sunbird_courses
-- ============================================================
--
-- All assessment attempts for a user, optionally filtered by course.

INSERT INTO standard_reports_meta (
    report_id,
    title,
    description,
    domain,
    data_source,
    query_template,
    supported_filters,
    enabled,
    aggregation_spec
) VALUES (
    'user-assessment-summary',
    'User Assessment History',
    'All assessment attempts for a user, optionally filtered by course',
    'consumption',
    'YUGABYTE_CQL',
    'SELECT course_id, batch_id, content_id, attempt_id, total_score, total_max_score, last_attempted_on
  FROM sunbird_courses.assessment_aggregator
  WHERE user_id = {{userid}}
  {{#courseid}}AND course_id = {{courseid}}{{/courseid}}',
    '["userid", "courseid"]',
    TRUE,
    NULL
) ON CONFLICT (report_id) DO NOTHING;

-- ============================================================
-- Report: user-course-enrolments
-- Data Source: YUGABYTE_CQL
-- Keyspace: sunbird_courses
-- ============================================================
--
-- All course enrolments for a user with progress and status info.

INSERT INTO standard_reports_meta (
    report_id,
    title,
    description,
    domain,
    data_source,
    query_template,
    supported_filters,
    enabled,
    aggregation_spec
) VALUES (
    'user-course-enrolments',
    'User Course Enrolments',
    'All course enrolments for a user with progress and status info',
    'consumption',
    'YUGABYTE_CQL',
    'SELECT courseid, completionpercentage, status, enrolled_date, datetime, issued_certificates
  FROM sunbird_courses.user_enrolments
  WHERE userid = {{userid}}',
    '["userid"]',
    TRUE,
    NULL
) ON CONFLICT (report_id) DO NOTHING;

-- ============================================================
-- Report: user-creation-count
-- Data Source: ELASTICSEARCH
-- ============================================================
--
-- Count of users created within a date range.

INSERT INTO standard_reports_meta (
    report_id,
    title,
    description,
    domain,
    data_source,
    query_template,
    supported_filters,
    enabled,
    aggregation_spec
) VALUES (
    'user-creation-count',
    'User Creation Count by Date Range',
    'Count of users created within a date range',
    'user_profile',
    'ELASTICSEARCH',
    '{"fromDate":"{{fromDate}}","toDate":"{{toDate}}"}',
    '["fromDate", "toDate"]',
    TRUE,
    NULL
) ON CONFLICT (report_id) DO NOTHING;

-- ============================================================
-- Report: user-consent-summary
-- Data Source: YUGABYTE_CQL
-- Keyspace: sunbird
-- ============================================================
--
-- Scans all rows in the user_consent table. No filters applied — returns full table.

INSERT INTO standard_reports_meta (
    report_id,
    title,
    description,
    domain,
    data_source,
    query_template,
    supported_filters,
    enabled,
    aggregation_spec
) VALUES (
    'user-consent-summary',
    'User Consent',
    'Returns all user consent records including status, consumer, object, and timestamps.',
    'user',
    'YUGABYTE_CQL',
    'SELECT user_id, object_id, status, created_on, expiry FROM sunbird.user_consent',
    '[]',
    TRUE,
    NULL
) ON CONFLICT (report_id) DO NOTHING;