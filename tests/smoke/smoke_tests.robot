*** Settings ***
Documentation     Smoke tests for the thesis CI/CD pipeline.
...               These tests exercise the deployed services from outside the
...               cluster, through the api-gateway NodePort. A passing run
...               indicates the deployment is healthy; the scenario harness
...               triggers a rollback when these tests fail.
Resource          resources/keywords.robot
Library           Collections
Suite Setup       Open Gateway Session

*** Test Cases ***
api-gateway /health endpoint returns 200
    [Documentation]    The gateway's own liveness endpoint must report healthy.
    ${response}=    Get Health    /health
    Should Be Equal As Integers    ${response.status_code}    200
    Should Be Equal    ${response.json()}[status]    healthy

user-service /health endpoint returns 200
    [Documentation]    user-service is ClusterIP-only, so its health is verified
    ...                transitively: the gateway's /ready endpoint returns 200
    ...                only when user-service /health is reachable and healthy.
    ${response}=    Get Health    /ready
    Should Be Equal As Integers    ${response.status_code}    200
    Should Be Equal    ${response.json()}[dependencies][user-service]    healthy

GET /api/users returns user list
    [Documentation]    Verifies inter-service communication: the gateway proxies
    ...                the request through to user-service and returns its list.
    ${response}=    Get All Users
    Should Be Equal As Integers    ${response.status_code}    200
    Dictionary Should Contain Key    ${response.json()}    users
    Should Not Be Empty    ${response.json()}[users]

POST /api/users creates a new user
    [Documentation]    Creates a user through the gateway proxy and checks the
    ...                created object is echoed back with an assigned id.
    ${response}=    Create Test User    Smoke Tester    smoke@example.com
    Should Be Equal As Integers    ${response.status_code}    201
    Should Be Equal    ${response.json()}[name]    Smoke Tester
    Should Be Equal    ${response.json()}[email]    smoke@example.com
    Dictionary Should Contain Key    ${response.json()}    id

Created user appears in the user list
    [Documentation]    Creates a user, then retrieves the full list and confirms
    ...                the new user is present. This is the externally-reachable
    ...                equivalent of retrieving a single user by id, since the
    ...                gateway exposes no per-user GET route.
    ${created}=    Create Test User    List Check    listcheck@example.com
    Should Be Equal As Integers    ${created.status_code}    201
    ${new_id}=    Set Variable    ${created.json()}[id]
    ${list}=    Get All Users
    Should Be Equal As Integers    ${list.status_code}    200
    ${ids}=    Evaluate    [u['id'] for u in $list.json()['users']]
    List Should Contain Value    ${ids}    ${new_id}
