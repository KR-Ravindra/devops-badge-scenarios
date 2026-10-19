"""Drives each lab's web UIs in a real browser through tests/browser/proxy.sh.

Usage: ui.py jenkins PORT JOB | mailpit PORT | minio PORT USER PASS | page PORT TEXT
Fails (exit 1) on anything a candidate would hit: CSRF rejections, redirects to
localhost, a UI that never loads.
"""
import sys, time
from playwright.sync_api import sync_playwright

def base(port):
    return f"https://lab-{port}.kc.test"

def stays_on(page, b):
    assert page.url.startswith(b), f"browser left the proxy host: {page.url}"

def jenkins(page, port, job):
    b = base(port)
    page.goto(b + "/login")
    page.fill("input[name=j_username]", "admin")
    page.fill("input[name=j_password]", "admin")
    page.keyboard.press("Enter")
    page.wait_for_load_state("networkidle")
    stays_on(page, b)
    assert "/login" not in page.url, f"login did not stick: {page.url}"
    api = lambda: page.request.get(f"{b}/job/{job}/api/json").json()
    before = api()["nextBuildNumber"]
    page.goto(f"{b}/job/{job}/")
    page.get_by_text("Build Now", exact=True).first.click()
    for _ in range(60):
        if api()["nextBuildNumber"] > before:
            break
        time.sleep(1)
    else:
        raise AssertionError("Build Now did not start a build: " + page.content()[:400])
    for _ in range(180):  # let it finish so later steps see a settled job
        if not page.request.get(f"{b}/job/{job}/lastBuild/api/json").json()["building"]:
            break
        time.sleep(1)
    # A form POST through the proxy (job config save) must also be accepted.
    page.goto(f"{b}/job/{job}/configure")
    with page.expect_response(lambda r: "/configSubmit" in r.url) as resp:
        page.get_by_role("button", name="Save").click()
    assert resp.value.status < 400, f"config save rejected: HTTP {resp.value.status}"
    page.wait_for_load_state("networkidle")
    stays_on(page, b)
    print(f"jenkins :{port} OK (login, Build Now, config save)")

def mailpit(page, port):
    b = base(port)
    sockets = []
    page.on("websocket", lambda ws: sockets.append(ws))
    page.goto(b + "/")
    page.wait_for_load_state("networkidle")
    time.sleep(3)
    stays_on(page, b)
    assert sockets and not sockets[0].is_closed(), "inbox live-update websocket did not stay open"
    assert page.request.get(b + "/api/v1/messages").ok
    print(f"mailpit :{port} OK (UI, websocket, API)")

def minio(page, port, user, pw):
    b = base(port)
    page.goto(b + "/")
    page.fill("#accessKey", user)
    page.fill("#secretKey", pw)
    page.keyboard.press("Enter")
    page.wait_for_url(lambda u: "/login" not in u, timeout=30000)
    stays_on(page, b)
    print(f"minio console :{port} OK (login)")

def text_page(page, port, text):
    b = base(port)
    page.goto(b + "/")
    stays_on(page, b)
    assert text in page.content(), f"'{text}' not on {b}"
    print(f"page :{port} OK")

if __name__ == "__main__":
    kind, *args = sys.argv[1:]
    with sync_playwright() as p:
        br = p.chromium.launch()
        page = br.new_context(ignore_https_errors=True).new_page()
        page.set_default_timeout(30000)
        {"jenkins": jenkins, "mailpit": mailpit, "minio": minio, "page": text_page}[kind](page, *args)
        br.close()
