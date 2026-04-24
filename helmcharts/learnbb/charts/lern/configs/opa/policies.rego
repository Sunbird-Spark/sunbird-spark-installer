package policies

import data.common as super
import future.keywords.in
import input.attributes.request.http as http_request

urls_to_action_mapping := {
  # lms
  "/v1/course/batch/update": "updateBatch",
  "/v1/user/courses/list": "listCourseEnrollments",
  "/v1/course/enroll": "courseEnrollment",
  "/v1/course/unenroll": "courseUnEnrollment",
  "/v1/content/state/read": "readContentState",
  "/v1/content/state/update": "updateContentState",
  "/v1/course/batch/cert/template/add": "courseBatchAddCertificateTemplate",
  "/v1/course/batch/cert/template/remove": "courseBatchRemoveCertificateTemplate",
  "/v1/course/batch/create": "createBatch",
  "/v1/course/batch/read": "getBatch",
  # userorg
  "/v1/user/tnc/accept": "acceptTermsAndCondition",
  "/v1/user/update": "updateUser",
  "/v1/user/assign/role": "assignRole",
  "/v2/user/assign/role": "assignRoleV2",
  "/v1/user/read": "getUserProfile",
  "/v2/user/read": "getUserProfileV2",
  "/v3/user/read": "getUserProfileV3",
  "/v4/user/read": "getUserProfileV4",
  "/v5/user/read": "getUserProfileV5",
  "/v1/user/feed": "userFeed",
  "/v1/user/feed/create": "userFeedCreate",
  "/v1/user/feed/delete": "userFeedDelete",
  "/v1/user/feed/update": "userFeedUpdate",
  "/v2/user/update": "updateUserV2",
  "/v3/user/update": "updateUserV3",
  "/v1/user/declarations": "updateUserDeclarations",
  "/v1/manageduser/create": "managedUserV1Create",
  "/v1/user/managed": "searchManagedUser",
  "/v1/user/consent/read": "readUserConsent",
  "/v1/user/consent/update": "updateUserConsent",
  "/v2/org/preferences/read": "readTenantPreferences",
  "/v2/org/preferences/create": "createTenantPreferences",
  "/v2/org/preferences/update": "updateTenantPreferences",
  # notification
  "/v1/notification/feed/read": "readNotificationFeed",
  "/v1/notification/feed/delete": "deleteNotificationFeed",
  "/v1/notification/feed/update": "updateNotificationFeed"
}

# --- Shared / Helpers ---

# --- LMS Actions ---
updateBatch {
  acls := ["updateBatch"]
  roles := ["CONTENT_CREATOR", "COURSE_CREATOR", "COURSE_MENTOR"]
  super.acls_check(acls)
  super.role_check(roles)
}

listCourseEnrollments {
  super.public_role_check
  user_id := split(http_request.path, "/")[5]
  split(user_id, "?")[0] == super.userid
}

courseEnrollment {
  super.public_role_check
  input.parsed_body.request.userId == super.userid
}

courseUnEnrollment {
  super.public_role_check
  input.parsed_body.request.userId == super.userid
}

readContentState {
  super.public_role_check
  input.parsed_body.request.userId == super.userid
}

readContentState {
  super.public_role_check
  not input.parsed_body.request.userId
}

updateContentState {
  super.public_role_check
  not input.parsed_body.request.assessments
  input.parsed_body.request.userId == super.userid
}

updateContentState {
  super.public_role_check
  not input.parsed_body.request.userId
  not input.parsed_body.request.assessments
}

updateContentState {
  super.public_role_check
  input.parsed_body.request.userId == super.userid
  assessment_userids := {ids | ids := input.parsed_body.request.assessments[_].userId}
  count(assessment_userids) == 1
  assessment_userids[super.userid] == super.userid
}

updateContentState {
  super.public_role_check
  not input.parsed_body.request.userId
  assessment_userids := {ids | ids := input.parsed_body.request.assessments[_].userId}
  count(assessment_userids) == 1
  assessment_userids[super.userid] == super.userid
}

courseBatchAddCertificateTemplate {
  acls := ["courseBatchAddCertificateTemplate"]
  roles := ["CONTENT_CREATOR", "COURSE_CREATOR", "COURSE_MENTOR"]
  super.acls_check(acls)
  super.role_check(roles)
}

courseBatchRemoveCertificateTemplate {
  acls := ["courseBatchRemoveCertificateTemplate"]
  roles := ["CONTENT_CREATOR", "COURSE_CREATOR", "COURSE_MENTOR"]
  super.acls_check(acls)
  super.role_check(roles)
}

createBatch {
  acls := ["createBatch"]
  roles := ["CONTENT_CREATOR", "COURSE_CREATOR", "COURSE_MENTOR"]
  super.acls_check(acls)
  super.role_check(roles)
}

getBatch {
  super.public_role_check
}

# --- UserOrg Actions ---
acceptTermsAndCondition {
  super.public_role_check
  not input.parsed_body.request.userId
  not input.parsed_body.request.tncType
}

acceptTermsAndCondition {
  super.public_role_check
  input.parsed_body.request.userId == super.userid
  not input.parsed_body.request.tncType
}

acceptTermsAndCondition {
  super.public_role_check
  not input.parsed_body.request.userId
  not input.parsed_body.request.tncType in ["orgAdminTnc", "reportViewerTnc"]
}

acceptTermsAndCondition {
  acls := ["acceptTnc"]
  roles := ["ORG_ADMIN"]
  super.acls_check(acls)
  super.role_check(roles)
  not input.parsed_body.request.userId
  "orgAdminTnc" == input.parsed_body.request.tncType
}

acceptTermsAndCondition {
  acls := ["acceptTnc"]
  roles := ["REPORT_VIEWER", "REPORT_ADMIN"]
  super.acls_check(acls)
  super.role_check(roles)
  not input.parsed_body.request.userId
  "reportViewerTnc" == input.parsed_body.request.tncType
}

acceptTermsAndCondition {
  super.public_role_check
  input.parsed_body.request.userId == super.userid
  not input.parsed_body.request.tncType in ["orgAdminTnc", "reportViewerTnc"]
}

acceptTermsAndCondition {
  acls := ["acceptTnc"]
  roles := ["ORG_ADMIN"]
  super.acls_check(acls)
  super.role_check(roles)
  input.parsed_body.request.userId == super.userid
  "orgAdminTnc" == input.parsed_body.request.tncType
}

acceptTermsAndCondition {
  acls := ["acceptTnc"]
  roles := ["REPORT_VIEWER", "REPORT_ADMIN"]
  super.acls_check(acls)
  super.role_check(roles)
  input.parsed_body.request.userId == super.userid
  "reportViewerTnc" == input.parsed_body.request.tncType
}

updateUser {
  super.public_role_check
  input.parsed_body.request.userId == super.userid
}

assignRole {
  acls := ["assignRole"]
  roles := ["ORG_ADMIN"]
  super.acls_check(acls)
  token_organisationids := super.org_check(roles)
  input.parsed_body.request.organisationId in token_organisationids
}

assignRoleV2 {
  acls := ["assignRole"]
  roles := ["ORG_ADMIN"]
  super.acls_check(acls)
  token_orgs := super.org_check(roles)
  payload_orgs := {ids | ids := input.parsed_body.request.roles[_].scope[_].organisationId}
  matching_orgs := {orgs | some i; payload_orgs[i] in token_orgs; orgs := i}
  payload_orgs == matching_orgs
}

assignRoleV2 {
  acls := ["assignRole"]
  roles := ["ORG_ADMIN"]
  super.acls_check(acls)
  type_name(input.parsed_body.request.roles[_].scope[_].organisationId) == "array"
}

getUserProfile {
  super.public_role_check
  user_id := split(http_request.path, "/")[4]
  split(user_id, "?")[0] == super.userid
}

getUserProfileV2 {
  super.public_role_check
  user_id := split(http_request.path, "/")[4]
  split(user_id, "?")[0] == super.userid
}

getUserProfileV3 {
  super.public_role_check
  user_id := split(http_request.path, "/")[4]
  split(user_id, "?")[0] == super.userid
}

getUserProfileV4 {
  super.public_role_check
  user_id := split(http_request.path, "/")[4]
  split(user_id, "?")[0] == super.userid
}

getUserProfileV5 {
  super.public_role_check
  user_id := split(http_request.path, "/")[4]
  split(user_id, "?")[0] == super.userid
}

getUserProfileV5 {
  acls := ["getUserProfileV5"]
  roles := ["ORG_ADMIN"]
  super.acls_check(acls)
  super.role_check(roles)
}

getUserProfileV5 {
  super.public_role_check
  contains(http_request.path, "?withTokens=true")
}

userFeed {
  super.public_role_check
  user_id := split(http_request.path, "/")[4]
  split(user_id, "?")[0] == super.userid
}

userFeedCreate { true }
userFeedDelete { true }
userFeedUpdate { true }

updateUserV2 {
  super.public_role_check
  input.parsed_body.request.userId == super.userid
}

updateUserV2 {
  acls := ["updateUserV2"]
  roles := ["ORG_ADMIN"]
  super.acls_check(acls)
  super.role_check(roles)
}

updateUserV3 {
  super.public_role_check
  input.parsed_body.request.userId == super.userid
}

updateUserDeclarations {
  super.public_role_check
  payload_userids := {ids | ids := input.parsed_body.request.declarations[_].userId}
  count(payload_userids) == 1
  payload_userids[super.userid] == super.userid
}

managedUserV1Create {
  super.public_role_check
  input.parsed_body.request.managedBy == super.for_token_parentid
}

managedUserV1Create {
  super.public_role_check
  input.parsed_body.request.managedBy == super.userid
}

searchManagedUser {
  super.public_role_check
  super.for_token_exists
  user_id := split(http_request.path, "/")[4]
  split(user_id, "?")[0] == super.for_token_parentid
}

searchManagedUser {
  super.public_role_check
  not super.for_token_exists
  user_id := split(http_request.path, "/")[4]
  split(user_id, "?")[0] == super.userid
}

readUserConsent {
  super.public_role_check
  input.parsed_body.request.consent.filters.userId == super.userid
}

readUserConsent {
  acls := ["readUserConsent"]
  roles := ["ORG_ADMIN"]
  super.acls_check(acls)
  super.role_check(roles)
}

updateUserConsent {
  super.public_role_check
  input.parsed_body.request.consent.userId == super.userid
}

readTenantPreferences {
  super.public_role_check
}

createTenantPreferences {
  acls := ["createTenantPreferences"]
  roles := ["ORG_ADMIN"]
  super.acls_check(acls)
  super.role_check(roles)
}

updateTenantPreferences {
  acls := ["updateTenantPreferences"]
  roles := ["ORG_ADMIN"]
  super.acls_check(acls)
  super.role_check(roles)
}

# --- Notification Actions ---
readNotificationFeed {
  super.public_role_check
  user_id := split(http_request.path, "/")[5]
  split(user_id, "?")[0] == super.userid
}

deleteNotificationFeed {
  super.public_role_check
  input.parsed_body.request.userId == super.userid
}

updateNotificationFeed {
  super.public_role_check
  input.parsed_body.request.userId == super.userid
}
