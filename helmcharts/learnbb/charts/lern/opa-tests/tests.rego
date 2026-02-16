package tests

# The tokens used in test cases expire on 1640236102
# So we set the current_time to a few minutes earlier than the expiry
# This will ensure the test cases succeed

current_time := 1640235102
iss := "https://sunbirded.org/auth/realms/sunbird"

test_accept_terms_and_conditions_as_org_admin {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/user/tnc/accept"
          }
        }
      },
      "parsed_body": {
        "request": {
          "tncType": "orgAdminTnc",
           "version": "4.7.0"
        }
      }
    }
}

test_accept_terms_and_conditions_as_org_admin_with_userid {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/user/tnc/accept"
          }
        }
      },
      "parsed_body": {
        "request": {
          "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
          "tncType": "orgAdminTnc",
           "version": "4.7.0"
        }
      }
    }
}

test_accept_terms_and_conditions_as_report_viewer {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/user/tnc/accept"
          }
        }
      },
      "parsed_body": {
        "request": {
          "tncType": "reportViewerTnc",
          "version": "4.7.0"
        }
      }
    }
}

test_accept_terms_and_conditions_as_report_viewer_with_userid {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/user/tnc/accept"
          }
        }
      },
      "parsed_body": {
        "request": {
          "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
          "tncType": "reportViewerTnc",
          "version": "4.7.0"
        }
      }
    }
}

test_accept_terms_and_conditions_as_public_user {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiUFVCTElDIiwic2NvcGUiOltdfV0sImlzcyI6Imh0dHBzOi8vc3VuYmlyZGVkLm9yZy9hdXRoL3JlYWxtcy9zdW5iaXJkIiwibmFtZSI6ImRlbW8iLCJ0eXAiOiJCZWFyZXIiLCJleHAiOjE2NDAyMzYxMDIsImlhdCI6MTY0MDE0OTcwNX0.iyFqdJG_9xF07S94bkfVDiWHmDWAmhCEmapu37Mto78s5OkOJQy-agXFjtQtgV5rFudHiVRukNpKXqlJ8GhasmW7fSEPL-fDKMilMIi4JCZi7d19AkFeq8mX0rI31m3zjCv-TcMPPWWNM4udR7kSj-tUOB-vupGZ1iRAtQU2lqrUCl1A84UYDqnJTokz6RVlr_Z4lRCzFn__aGsDZXO8h7juM4mAepVMy3wVhmbKR2R5WF5xQIvVjzEveRYj8P26VUg73wo_RtyRI5mQjbxyBaIX287pWe3kCu1KKwYQkBlRLx9da39g9TKZWXxD5ArCYMC83EmEeFI0LJicYDTXFg"
            },
            "path": "/v1/user/tnc/accept"
          }
        }
      },
      "parsed_body": {
        "request": {
          "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
          "version": "v8"
        }
      }
    }
}

test_accept_terms_and_conditions_as_public_user_without_userid {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiUFVCTElDIiwic2NvcGUiOltdfV0sImlzcyI6Imh0dHBzOi8vc3VuYmlyZGVkLm9yZy9hdXRoL3JlYWxtcy9zdW5iaXJkIiwibmFtZSI6ImRlbW8iLCJ0eXAiOiJCZWFyZXIiLCJleHAiOjE2NDAyMzYxMDIsImlhdCI6MTY0MDE0OTcwNX0.iyFqdJG_9xF07S94bkfVDiWHmDWAmhCEmapu37Mto78s5OkOJQy-agXFjtQtgV5rFudHiVRukNpKXqlJ8GhasmW7fSEPL-fDKMilMIi4JCZi7d19AkFeq8mX0rI31m3zjCv-TcMPPWWNM4udR7kSj-tUOB-vupGZ1iRAtQU2lqrUCl1A84UYDqnJTokz6RVlr_Z4lRCzFn__aGsDZXO8h7juM4mAepVMy3wVhmbKR2R5WF5xQIvVjzEveRYj8P26VUg73wo_RtyRI5mQjbxyBaIX287pWe3kCu1KKwYQkBlRLx9da39g9TKZWXxD5ArCYMC83EmEeFI0LJicYDTXFg"
            },
            "path": "/v1/user/tnc/accept"
          }
        }
      },
      "parsed_body": {
        "request": {
          "version": "v8"
        }
      }
    }
}

test_accept_terms_and_conditions_as_public_user_without_userid_other_tnc_types {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiUFVCTElDIiwic2NvcGUiOltdfV0sImlzcyI6Imh0dHBzOi8vc3VuYmlyZGVkLm9yZy9hdXRoL3JlYWxtcy9zdW5iaXJkIiwibmFtZSI6ImRlbW8iLCJ0eXAiOiJCZWFyZXIiLCJleHAiOjE2NDAyMzYxMDIsImlhdCI6MTY0MDE0OTcwNX0.iyFqdJG_9xF07S94bkfVDiWHmDWAmhCEmapu37Mto78s5OkOJQy-agXFjtQtgV5rFudHiVRukNpKXqlJ8GhasmW7fSEPL-fDKMilMIi4JCZi7d19AkFeq8mX0rI31m3zjCv-TcMPPWWNM4udR7kSj-tUOB-vupGZ1iRAtQU2lqrUCl1A84UYDqnJTokz6RVlr_Z4lRCzFn__aGsDZXO8h7juM4mAepVMy3wVhmbKR2R5WF5xQIvVjzEveRYj8P26VUg73wo_RtyRI5mQjbxyBaIX287pWe3kCu1KKwYQkBlRLx9da39g9TKZWXxD5ArCYMC83EmEeFI0LJicYDTXFg"
            },
            "path": "/v1/user/tnc/accept"
          }
        }
      },
      "parsed_body": {
        "request": {
          "version": "v8",
          "tncType": "groupsTnc"
        }
      }
    }
}

test_accept_terms_and_conditions_as_public_user_with_userid_other_tnc_types {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiUFVCTElDIiwic2NvcGUiOltdfV0sImlzcyI6Imh0dHBzOi8vc3VuYmlyZGVkLm9yZy9hdXRoL3JlYWxtcy9zdW5iaXJkIiwibmFtZSI6ImRlbW8iLCJ0eXAiOiJCZWFyZXIiLCJleHAiOjE2NDAyMzYxMDIsImlhdCI6MTY0MDE0OTcwNX0.iyFqdJG_9xF07S94bkfVDiWHmDWAmhCEmapu37Mto78s5OkOJQy-agXFjtQtgV5rFudHiVRukNpKXqlJ8GhasmW7fSEPL-fDKMilMIi4JCZi7d19AkFeq8mX0rI31m3zjCv-TcMPPWWNM4udR7kSj-tUOB-vupGZ1iRAtQU2lqrUCl1A84UYDqnJTokz6RVlr_Z4lRCzFn__aGsDZXO8h7juM4mAepVMy3wVhmbKR2R5WF5xQIvVjzEveRYj8P26VUg73wo_RtyRI5mQjbxyBaIX287pWe3kCu1KKwYQkBlRLx9da39g9TKZWXxD5ArCYMC83EmEeFI0LJicYDTXFg"
            },
            "path": "/v1/user/tnc/accept"
          }
        }
      },
      "parsed_body": {
        "request": {
          "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
          "version": "v8",
          "tncType": "groupsTnc"
        }
      }
    }
}

test_update_user {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/user/update"
          }
        }
      },
      "parsed_body": {
        "request": {
          "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be"
        }
      }
    }
}

test_assign_role {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/user/assign/role"
          }
        }
      },
      "parsed_body": {
        "request": {
          "organisationId": "01369878797503692810",
          "userId": "fcae65a6-8a48-11ec-8c82-c7075e84952d",
          "roles": ["CONTENT_REVIEWER"]
        }
      }
    }
}

test_assign_role_v2 {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v2/user/assign/role"
          }
        }
      },
      "parsed_body": {
        "request": {
          "userId": "fcae65a6-8a48-11ec-8c82-c7075e84952d",
          "roles": [{
            "role": "COURSE_CREATOR",
            "operation":"remove",
            "scope": [{
              "organisationId": "01369878797503692810"
            }]
          },
          {
            "role": "CONTENT_CREATOR",
            "operation":"add",
            "scope": [{
              "organisationId": "01471923567812345678"
            }]
          }]
        }
      }
    }
}

test_assign_role_v2 {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v2/user/assign/role"
          }
        }
      },
      "parsed_body": {
        "request": {
          "userId": "fcae65a6-8a48-11ec-8c82-c7075e84952d",
          "roles": [{
            "role": "COURSE_CREATOR",
            "operation":"remove",
            "scope": [{
              "organisationId": "01369878797503692810"
            }]
          },
          {
            "role": "CONTENT_CREATOR",
            "operation":"add",
            "scope": [{
              "organisationId": ["01471923567812345678"]
            }]
          }]
        }
      }
    }
}

test_get_user_profile {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/user/read/28b0d08f-c2ea-40d1-bcd0-8ae00fca66be?fields=organisations,roles,locations,declarations,externalIds"
          }
        }
      }
    }
}

test_get_user_profile_v2 {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v2/user/read/28b0d08f-c2ea-40d1-bcd0-8ae00fca66be?fields=organisations,roles,locations,declarations,externalIds"
          }
        }
      }
    }
}

test_get_user_profile_v3 {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v3/user/read/28b0d08f-c2ea-40d1-bcd0-8ae00fca66be?fields=organisations,roles,locations,declarations,externalIds"
          }
        }
      }
    }
}

test_get_user_profile_v4 {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v4/user/read/28b0d08f-c2ea-40d1-bcd0-8ae00fca66be?fields=organisations,roles,locations,declarations,externalIds"
          }
        }
      }
    }
}

test_get_user_profile_v5_as_public_user {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v5/user/read/28b0d08f-c2ea-40d1-bcd0-8ae00fca66be?fields=organisations,roles,locations,declarations,externalIds"
          }
        }
      }
    }
}

test_get_user_profile_v5_as_org_admin {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v5/user/read/81c28eac-bf0f-11ec-8e6f-4f07103b952d?fields=organisations,roles,locations,declarations,externalIds"
          }
        }
      }
    }
}

test_get_user_profile_v5_with_tokens_in_query_params {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v5/user/read/81c28eac-bf0f-11ec-8e6f-4f07103b952d?withTokens=true"
          }
        }
      }
    }
}

test_get_user_feed {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/user/feed/28b0d08f-c2ea-40d1-bcd0-8ae00fca66be"
          }
        }
      }
    }
}

test_get_user_feed_create {
    data.main.allow.allowed
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "path": "/v1/user/feed/create"
          }
        }
      }
    }
}


test_get_user_feed_delete {
    data.main.allow.allowed
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "path": "/v1/user/feed/delete"
          }
        }
      }
    }
}


test_get_user_feed_update {
    data.main.allow.allowed
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "path": "/v1/user/feed/update"
          }
        }
      }
    }
}


test_update_user_v2_as_public_user {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v2/user/update"
          }
        }
      },
      "parsed_body": {
        "request": {
          "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be"
        }
      }
    }
}

test_update_user_v2_as_org_admin {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v2/user/update"
          }
        }
      },
      "parsed_body": {
        "request": {
          "userId": "81c28eac-bf0f-11ec-8e6f-4f07103b952d"
        }
      }
    }
}

test_update_user_v3 {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v3/user/update"
          }
        }
      },
      "parsed_body": {
        "request": {
          "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be"
        }
      }
    }
}

test_update_user_declarations {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/user/declarations"
          }
        }
      },
      "parsed_body": {
        "params": {},
        "request": {
          "declarations": [
            {
              "operation": "add",
              "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
              "orgId": "01297544481264435214",
              "persona": "teacher",
              "info": {
                "declared-school-name": "mgm21",
                "declared-email": "abc@gmail.com",
                "declared-phone": 99999999,
                "declared-school-udise-code": 190923
              }
            }
          ]
        }
      }
    }
}

test_managed_user_v1_create_with_for_token {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww",
              "x-authenticated-for": "eyJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTUifQ.eyJwYXJlbnRJZCI6IjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInN1YiI6IjgwYzM0YzdmLTViYXktNTY0ZS05MDhiLWJmYzA0MTAzODEwZCIsImV4cCI6MTcwMTUxNDA4NSwiaWF0IjoxNjM4NDQyMDg1fQ.skXXt_p2N_0EYQ500Z-xAwdZxoS3MzmVWBhsfSw7ff_QzHciKw21ICDNVnHHOXd_Akf2IA9jUP1lyrBLPRtFrLfYMLjlZB65L2r34QGpBTgkaLhacA_yv7h0neHNHT3D_KO3YKDAdycdAGzTDQZ9BJ1iDtBLc8Qu9VEdRZOQvQf11jotHZf3UEvY3zrpIrghYAfUbTR3kPFp2W_1CJDixWiKgm8IfEJSpzzCHH2RPKPDdyIbY-9eEHGkeTPqtyCNx_vgOLZg5ieJGwyvhH6KRMJ5y1fgXXv0kadZsp7h3nrDSkd3uONStFxdUdIzIIjvJHqjpDFa5NkQbbY0iIULvw"
            },
            "path": "/v1/manageduser/create"
          }
        }
      },
      "parsed_body": {
        "request": {
          "firstName": "My Child",
          "managedBy": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
          "profileLocation": [
            {
              "code": "02,",
              "type": "state"
            },
            {
              "code": "0211,",
              "type": "district"
            }
          ]
        }
      }
    }
}

test_managed_user_v1_create_without_for_token {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/manageduser/create"
          }
        }
      },
      "parsed_body": {
        "request": {
          "firstName": "My Child",
          "managedBy": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
          "profileLocation": [
            {
              "code": "02,",
              "type": "state"
            },
            {
              "code": "0211,",
              "type": "district"
            }
          ]
        }
      }
    }
}

test_search_managed_user_with_for_token {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww",
              "x-authenticated-for": "eyJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTUifQ.eyJwYXJlbnRJZCI6IjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInN1YiI6IjgwYzM0YzdmLTViYXktNTY0ZS05MDhiLWJmYzA0MTAzODEwZCIsImV4cCI6MTcwMTUxNDA4NSwiaWF0IjoxNjM4NDQyMDg1fQ.skXXt_p2N_0EYQ500Z-xAwdZxoS3MzmVWBhsfSw7ff_QzHciKw21ICDNVnHHOXd_Akf2IA9jUP1lyrBLPRtFrLfYMLjlZB65L2r34QGpBTgkaLhacA_yv7h0neHNHT3D_KO3YKDAdycdAGzTDQZ9BJ1iDtBLc8Qu9VEdRZOQvQf11jotHZf3UEvY3zrpIrghYAfUbTR3kPFp2W_1CJDixWiKgm8IfEJSpzzCHH2RPKPDdyIbY-9eEHGkeTPqtyCNx_vgOLZg5ieJGwyvhH6KRMJ5y1fgXXv0kadZsp7h3nrDSkd3uONStFxdUdIzIIjvJHqjpDFa5NkQbbY0iIULvw"
            },
            "path": "/v1/user/managed/28b0d08f-c2ea-40d1-bcd0-8ae00fca66be?sortBy=createdDate&order=desc"
          }
        }
      }
    }
}

test_search_managed_user_without_for_token {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/user/managed/28b0d08f-c2ea-40d1-bcd0-8ae00fca66be?sortBy=createdDate&order=desc"
          }
        }
      }
    }
}

test_read_user_consent_as_public_user {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/user/consent/read"
          }
        }
      },
      "parsed_body": {
        "request": {
          "consent": {
            "filters": {
              "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
              "consumerId": "0126632859575746566",
              "objectId": "0126632859575746566"
            }
          }
        }
      }
    }
}

test_read_user_consent_as_org_admin {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/user/consent/read"
          }
        }
      },
      "parsed_body": {
        "request": {
          "consent": {
            "filters": {
              "userId": "81c28eac-bf0f-11ec-8e6f-4f07103b952d",
              "consumerId": "0126632859575746566",
              "objectId": "0126632859575746566"
            }
          }
        }
      }
    }
}

test_update_user_consent {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/user/consent/update"
          }
        }
      },
      "parsed_body": {
        "request": {
          "consent": {
            "status": "ACTIVE",
            "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
            "consumerId": "0126632859575746566",
            "objectId": "0126632859575746566",
            "objectType": "Organisation"
          }
        }
      }
    }
}

test_read_tenant_preferences {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v2/org/preferences/read"
          }
        }
      },
      "parsed_body": {
        "request": {
          "orgId": "all",
          "key": "selfdeclarations"
        }
      }
    }
}

test_create_tenant_preferences {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v2/org/preferences/create"
          }
        }
      },
      "parsed_body": {
        "request": {
          "orgId": "all",
          "key": "selfdeclarations",
          "data": "Tenant preference data"
        }
      }
    }
}

test_update_tenant_preferences {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v2/org/preferences/update"
          }
        }
      },
      "parsed_body": {
        "request": {
          "orgId": "all",
          "key": "selfdeclarations",
          "data": "Tenant preference data"
        }
      }
    }
}
# The tokens used in test cases expire on 1640236102
# So we set the current_time to a few minutes earlier than the expiry
# This will ensure the test cases succeed


test_update_batch {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/course/batch/update"
          }
        }
      },
      "parsed_body": {
        "request": {
          "id": "0132861256891351040",
          "courseId": "do_113243615177629696188",
          "name": "test update -1",
          "description": null,
          "enrollmentType": "open",
          "startDate": "2021-05-20",
          "endDate": "2021-05-27",
          "mentors": ["95e4942d-cbe8-477d-aebd-ad8e6de4bfc8"],
          "tandc": true
        }
      }
    }
}

test_list_course_enrollments {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/user/courses/list/28b0d08f-c2ea-40d1-bcd0-8ae00fca66be?orgdetails=orgName,email&licenseDetails=name,description,url&fields=contentType,topic,name,channel,mimeType,appIcon,gradeLevel,resourceType,identifier,medium,pkgVersion,board,subject,trackable,primaryCategory,organisation&batchDetails=name,endDate,startDate,status,enrollmentType,createdBy,certificates"
          }
        }
      }
    }
}

test_course_enrollment {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/course/enroll"
          }
        }
      },
      "parsed_body": {
        "request": {
          "batchId": "0129889020926115845",
          "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
          "courseId": "do_11296619016047820818"
        }
      }
    }
}

test_course_unenrollment {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/course/unenroll"
          }
        }
      },
      "parsed_body": {
        "request": {
          "batchId": "0129889020926115845",
          "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
          "courseId": "do_11296619016047820818"
        }
      }
    }
}

test_read_content_state_with_userid {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/content/state/read"
          }
        }
      },
      "parsed_body": {
        "request": {
          "batchId": "0129889020926115845",
          "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
          "courseId": "do_11296619016047820818"
        }
      }
    }
}

test_read_content_state_without_userid {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/content/state/read"
          }
        }
      },
      "parsed_body": {
        "request": {
          "batchId": "0129889020926115845",
          "courseId": "do_11296619016047820818"
        }
      }
    }
}

test_update_content_state_with_userid_without_assessments {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/content/state/update"
          }
        }
      },
      "parsed_body": {
        "request": {
          "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
          "contents": [{
            "contentId": "do_2132720527261450241456",
            "batchId": "01328184204133990415",
            "status": 2,
            "courseId": "do_2132818357077442561633",
            "lastAccessTime": "2021-05-17 16:02:50:798+0530"
          }]
        }
      }
    }
}

test_update_content_state_without_userid_without_assessments {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/content/state/update"
          }
        }
      },
      "parsed_body": {
        "request": {
          "contents": [{
            "contentId": "do_2132720527261450241456",
            "batchId": "01328184204133990415",
            "status": 2,
            "courseId": "do_2132818357077442561633",
            "lastAccessTime": "2021-05-17 16:02:50:798+0530"
          }]
        }
      }
    }
}

test_update_content_state_with_userid_with_assessments {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/content/state/update"
          }
        }
      },
      "parsed_body": {
        "request": {
          "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
          "contents": [{
            "contentId": "do_2132720527261450241456",
            "batchId": "01328184204133990415",
            "status": 2,
            "courseId": "do_2132818357077442561633",
            "lastAccessTime": "2021-05-17 16:02:50:798+0530"
          }],
          "assessments": [
            {
            "assessmentTs": 1621247557820,
            "batchId": "01328184204133990415",
            "courseId": "do_2132818357077442561633",
            "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
            "attemptId": "9b520f8b329b3169f439ec587746ceee",
            "contentId": "do_2132720527261450241456",
            "events": [{}]
            },
            {
            "assessmentTs": 1621247557821,
            "batchId": "01328184204133990416",
            "courseId": "do_2132818357077442561634",
            "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
            "attemptId": "9b520f8b329b3169f439ec587746ceeg",
            "contentId": "do_2132720527261450241457",
            "events": [{}]
            }
          ]
        }
      }
    }
}

test_update_content_state_without_userid_with_assessments {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/content/state/update"
          }
        }
      },
      "parsed_body": {
        "request": {
          "contents": [{
            "contentId": "do_2132720527261450241456",
            "batchId": "01328184204133990415",
            "status": 2,
            "courseId": "do_2132818357077442561633",
            "lastAccessTime": "2021-05-17 16:02:50:798+0530"
          }],
          "assessments": [
            {
            "assessmentTs": 1621247557820,
            "batchId": "01328184204133990415",
            "courseId": "do_2132818357077442561633",
            "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
            "attemptId": "9b520f8b329b3169f439ec587746ceee",
            "contentId": "do_2132720527261450241456",
            "events": [{}]
            },
            {
            "assessmentTs": 1621247557821,
            "batchId": "01328184204133990416",
            "courseId": "do_2132818357077442561634",
            "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
            "attemptId": "9b520f8b329b3169f439ec587746ceeg",
            "contentId": "do_2132720527261450241457",
            "events": [{}]
            }
          ]
        }
      }
    }
}

test_course_batch_add_certificate_template {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/course/batch/cert/template/add"
          }
        }
      },
      "parsed_body": {
        "request": {
          "batch": {
            "courseId": "string",
            "batchId": "string",
            "template": {
              "identifier": "string",
              "criteria": {
                "enrollment": {
                  "status": "2"
                }
              },
              "signatoryList": [
                {
                  "name": "string",
                  "id": "string",
                  "designation": "CEO",
                  "image": "string"
                }
              ],
              "issuer": {
                "name": "string",
                "url": "string",
                "publicKey": [7, 8]
              }
            }
          }
        }
      }
    }
}

test_course_batch_remove_certificate_template {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/course/batch/cert/template/remove"
          }
        }
      },
      "parsed_body": {
        "request": {
          "batch": {
            "courseId": "courseId",
            "batchId": "batchId",
            "template": {
              "identifier": "template Identifier"
            }
          }
        }
      }
    }
}

test_create_batch {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/course/batch/create"
          }
        }
      },
      "parsed_body": {
        "request": {
          "courseId": "do_2132818357077442561633",
          "name": "test cert scalability",
          "description": "batch description1",
          "enrollmentType": "open",
          "startDate": "2020-11-23",
          "endDate": "2021-12-30"
        }
      }
    }
}

test_get_batch {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/course/batch/read/do_2132818357077442561633"
          }
        }
      }
    }
}

# The tokens used in test cases expire on 1640236102
# So we set the current_time to a few minutes earlier than the expiry
# This will ensure the test cases succeed


test_read_notification_feed {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/notification/feed/read/28b0d08f-c2ea-40d1-bcd0-8ae00fca66be"
          }
        }
      }
    }
}

test_delete_notification_feed {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/notification/feed/delete"
          }
        }
      },
      "parsed_body": {
        "request": {
          "ids": ["f1493e8b-9584-4c3d-bf5d-d227a3926853"],
          "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
          "category": "group-feed"
        }
      }
    }
}

test_update_notification_feed {
    data.main.allow.allowed
    with data.common.current_time as current_time
    with data.common.iss as iss
    with input as
    {
      "attributes": {
        "request": {
          "http": {
            "headers": {
              "x-authenticated-user-token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImFjY2Vzc3YxX2tleTEifQ.eyJhdWQiOiJodHRwczovL3N1bmJpcmRlZC5vcmcvYXV0aC9yZWFsbXMvc3VuYmlyZCIsInN1YiI6ImY6NWJiNmM4N2MtN2M4OC00ZDJiLWFmN2UtNTM0YTJmZWY5NzhkOjI4YjBkMDhmLWMyZWEtNDBkMS1iY2QwLThhZTAwZmNhNjZiZSIsInJvbGVzIjpbeyJyb2xlIjoiQk9PS19DUkVBVE9SIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPTlRFTlRfQ1JFQVRPUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJDT05URU5UX1JFVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6IkNPVVJTRV9NRU5UT1IiLCJzY29wZSI6W3sib3JnYW5pc2F0aW9uSWQiOiIwMTM2OTg3ODc5NzUwMzY5MjgxMCJ9XX0seyJyb2xlIjoiUFJPR1JBTV9ERVNJR05FUiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn1dfSx7InJvbGUiOiJSRVBPUlRfVklFV0VSIiwic2NvcGUiOlt7Im9yZ2FuaXNhdGlvbklkIjoiMDEzNjk4Nzg3OTc1MDM2OTI4MTAifV19LHsicm9sZSI6Ik9SR19BRE1JTiIsInNjb3BlIjpbeyJvcmdhbmlzYXRpb25JZCI6IjAxMzY5ODc4Nzk3NTAzNjkyODEwIn0seyJvcmdhbmlzYXRpb25JZCI6IjAxNDcxOTIzNTY3ODEyMzQ1Njc4In1dfSx7InJvbGUiOiJQVUJMSUMiLCJzY29wZSI6W119XSwiaXNzIjoiaHR0cHM6Ly9zdW5iaXJkZWQub3JnL2F1dGgvcmVhbG1zL3N1bmJpcmQiLCJuYW1lIjoiZGVtbyIsInR5cCI6IkJlYXJlciIsImV4cCI6MTY0MDIzNjEwMiwiaWF0IjoxNjQwMTQ5NzA1fQ.B3-TSdYSOlawPHjFdiRjXwvRbYQ_eH_HTiLKlH7vGS0rCOJ6HQbYyWOhZ7vbZPb3virkuyfhykFcYCEHBCkHY-fwGAeU58Pmhi0dnNJkR59Fa9y_75W98JXZW68HROp62ntEAKCA1oot_U4tYi-8UNoR17Gszj9iYzFEBc6TZA4Lrom_9gqhBOYzL0ISFWSS6oG94EaaKDYHyWzCSjU2nYRB_fn-tODmnVJ12GRJAc1oM9y54o8neNYsl4T_xPyD34v-CinUJM8jzDjFqK5_O3HnAbcmXvkZjFRgfk4mF1V4s5hlsTJGyhi2JOPh90C5N-HbAY8QsPBnzgYFQU_sww"
            },
            "path": "/v1/notification/feed/update"
          }
        }
      },
      "parsed_body": {
        "request": {
            "ids": ["f1493e8b-9584-4c3d-bf5d-d227a3926853"],
            "userId": "28b0d08f-c2ea-40d1-bcd0-8ae00fca66be",
            "category": "group-feed",
            "priority":1,
            "data":{
                "data":"user feed updated"
            }
        }
      }
    }
}
