*** Settings ***
Documentation     Reusable keywords for the thesis CI/CD smoke test suite.
...               These keywords wrap the HTTP calls so the test cases stay
...               readable and the base URL handling lives in one place.
Library           RequestsLibrary
Library           Collections
Library           OperatingSystem

*** Variables ***
${API_GATEWAY_URL}    %{API_GATEWAY_URL=http://localhost:30080}
${SESSION}            gateway

*** Keywords ***
Open Gateway Session
    [Documentation]    Creates an HTTP session against the api-gateway NodePort.
    ...                Called once in suite setup.
    Create Session    ${SESSION}    ${API_GATEWAY_URL}    verify=${True}

Get Health
    [Documentation]    Calls an endpoint on the api-gateway and returns the response.
    [Arguments]    ${path}
    ${response}=    GET On Session    ${SESSION}    ${path}    expected_status=any
    RETURN    ${response}

Get All Users
    [Documentation]    Retrieves the user list through the gateway proxy.
    ${response}=    GET On Session    ${SESSION}    /api/users    expected_status=any
    RETURN    ${response}

Create Test User
    [Documentation]    Creates a new user through the gateway proxy and returns
    ...                the created user object from the response body.
    [Arguments]    ${name}    ${email}
    ${payload}=    Create Dictionary    name=${name}    email=${email}
    ${response}=    POST On Session    ${SESSION}    /api/users    json=${payload}
    ...    expected_status=any
    RETURN    ${response}
