#!/usr/bin/env python3
"""
End-to-end ASC API driver for SleepWindow.

Subcommands:
  iap         create the $7.99 lifetime non-consumable IAP
  metadata    set the version localization (description, keywords, subtitle, promo, support URL, marketing URL)
  screenshots upload PNG files to the 6.9" iPhone Pro screenshot set
  privacy     set the privacy policy URL on the app info
  territory   set price/availability (stubbed; ASC API is limited here)
  status      print current app state (version, localizations, IAPs, screenshots)

Requires:
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (optional), APP_ID (defaults to SleepWindow's ID).
"""
import os, sys, json, time, urllib.request, urllib.parse, mimetypes, io, pathlib
import jwt

APP_ID = os.environ.get("APP_ID", "6762465676")
KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
KEY_PATH = os.environ.get("ASC_KEY_PATH", f"{os.path.expanduser('~')}/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")
BASE = "https://api.appstoreconnect.apple.com"

BUNDLE_ID = "com.sleepwindow.app"
LIFETIME_PRODUCT_ID = "com.sleepwindow.app.lifetime"


def token():
    with open(KEY_PATH, "rb") as f:
        key = f.read()
    return jwt.encode(
        {"iss": ISSUER, "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"},
    )


def request(method, path, body=None, *, params=None, extra_headers=None, raw=False):
    if params:
        path = path + "?" + urllib.parse.urlencode(params, safe="[]")
    url = path if path.startswith("http") else BASE + path
    headers = {"Authorization": f"Bearer {token()}"}
    if body is not None and not raw:
        body = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if extra_headers:
        headers.update(extra_headers)
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as r:
            raw_bytes = r.read()
            if not raw_bytes:
                return {}
            if r.headers.get("Content-Type", "").startswith("application/json"):
                return json.loads(raw_bytes)
            return raw_bytes
    except urllib.error.HTTPError as e:
        body_s = e.read().decode(errors="replace")
        print(f"HTTP {e.code} {method} {url}\n{body_s}", file=sys.stderr)
        raise


# ---------------------------------------------------------------- IAP

def ensure_iap_localization(iap_id):
    print("  creating/ensuring en-US localization ...")
    try:
        resp = request("POST", "/v1/inAppPurchaseLocalizations", {
            "data": {
                "type": "inAppPurchaseLocalizations",
                "attributes": {
                    "locale": "en-US",
                    "name": "SleepWindow Lifetime Unlock",
                    "description": "One-time unlock. All calculators & reminders.",
                },
                "relationships": {
                    "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}},
                },
            }
        })
        print(f"    -> created {resp['data']['id']}")
        return resp["data"]["id"]
    except urllib.error.HTTPError as e:
        if e.code == 409:
            print("    localization already exists")
            return None
        raise


def upload_iap_review_screenshot(iap_id, path):
    path = pathlib.Path(path)
    data = path.read_bytes()
    print(f"  uploading IAP review screenshot {path.name} ({len(data)} bytes) ...")
    resp = request("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", {
        "data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots",
            "attributes": {"fileName": path.name, "fileSize": len(data)},
            "relationships": {
                "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}},
            },
        }
    })
    shot_id = resp["data"]["id"]
    ops = resp["data"]["attributes"]["uploadOperations"]
    upload_asset(ops, data)
    request("PATCH", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{shot_id}", {
        "data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots",
            "id": shot_id,
            "attributes": {"uploaded": True, "sourceFileChecksum": None},
        }
    })
    print(f"    -> {shot_id}")


def cmd_iap_screenshot(path="docs/screenshots/paywall.png"):
    existing = request("GET", f"/v1/apps/{APP_ID}/inAppPurchasesV2",
                       params={"filter[productId]": LIFETIME_PRODUCT_ID})
    if not existing.get("data"):
        print("IAP not found; run 'iap' first")
        return
    iap_id = existing["data"][0]["id"]
    upload_iap_review_screenshot(iap_id, path)


def ensure_iap_price(iap_id, customer_price="7.99", territory="USA"):
    # Price point lookup uses v2 path for v2-created IAPs; schema here is fiddly
    # across Apple API versions so we fetch via the v2 per-product price points.
    try:
        schedule = request("GET", f"/v2/inAppPurchases/{iap_id}/pricePoints",
                           params={"filter[territory]": territory, "limit": 200})
    except urllib.error.HTTPError:
        print("  could not list price points via API; set price in ASC UI (one click)")
        return
    target = None
    for p in schedule.get("data", []):
        if p["attributes"].get("customerPrice") == customer_price:
            target = p["id"]
            break
    if not target:
        print(f"  no {territory} price point matches {customer_price}; set price in ASC UI")
        return
    # Check if schedule already set
    try:
        existing = request("GET", f"/v1/inAppPurchases/{iap_id}/iapPriceSchedule")
        if existing.get("data"):
            print(f"  price schedule already set")
            return
    except Exception:
        pass
    print(f"  setting price to {customer_price} {territory} ...")
    try:
        request("POST", "/v1/inAppPurchasePriceSchedules", {
            "data": {
                "type": "inAppPurchasePriceSchedules",
                "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                    "baseTerritory": {"data": {"type": "territories", "id": territory}},
                    "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price1}"}]},
                },
            },
            "included": [{
                "id": "${price1}",
                "type": "inAppPurchasePrices",
                "attributes": {"startDate": None},
                "relationships": {
                    "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": target}},
                },
            }],
        })
        print("    -> price saved")
    except Exception as e:
        print(f"    price schedule write failed ({e}); complete manually in ASC")


def cmd_iap():
    """Create the lifetime non-consumable IAP if it doesn't exist, and ensure
    localization + price are filled in."""
    existing = request("GET", f"/v1/apps/{APP_ID}/inAppPurchasesV2",
                       params={"filter[productId]": LIFETIME_PRODUCT_ID})
    if existing.get("data"):
        iap = existing["data"][0]
        iap_id = iap["id"]
        print(f"IAP exists: {iap_id} state={iap['attributes']['state']}")
        ensure_iap_localization(iap_id)
        ensure_iap_price(iap_id)
        return iap_id

    print("Creating IAP ...")
    body = {
        "data": {
            "type": "inAppPurchases",
            "attributes": {
                "name": "Lifetime Unlock",
                "productId": LIFETIME_PRODUCT_ID,
                "inAppPurchaseType": "NON_CONSUMABLE",
                "reviewNote": "Unlocks all calculators, nap planner, caffeine cutoff, unlimited reminders and presets. One-time purchase, no subscription.",
                "familySharable": False,
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": APP_ID}},
            },
        }
    }
    resp = request("POST", "/v2/inAppPurchases", body)
    iap_id = resp["data"]["id"]
    print(f"Created IAP: {iap_id}")

    # Localization
    print("Adding en-US localization ...")
    request("POST", "/v1/inAppPurchaseLocalizations", {
        "data": {
            "type": "inAppPurchaseLocalizations",
            "attributes": {
                "locale": "en-US",
                "name": "SleepWindow Lifetime Unlock",
                "description": "One-time purchase. Unlock every calculator, nap planner, caffeine cutoff, and unlimited reminders and saved presets. No subscription.",
            },
            "relationships": {
                "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}},
            },
        }
    })

    # Price point: tier 8 = $7.99 in US storefront
    print("Setting price to $7.99 (USD tier 8) ...")
    price_points = request("GET", f"/v1/inAppPurchases/{iap_id}/pricePoints",
                           params={"filter[territory]": "USA", "limit": 200})
    target = None
    for p in price_points.get("data", []):
        cust = p["attributes"]["customerPrice"]
        if cust == "7.99":
            target = p["id"]
            break
    if not target:
        print("  could not find a $7.99 price point for USA; prices will need to be set in ASC UI")
    else:
        # Creating the price schedule
        request("POST", "/v1/inAppPurchasePriceSchedules", {
            "data": {
                "type": "inAppPurchasePriceSchedules",
                "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                    "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                    "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price1}"}]},
                },
            },
            "included": [{
                "id": "${price1}",
                "type": "inAppPurchasePrices",
                "attributes": {"startDate": None},
                "relationships": {
                    "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": target}},
                },
            }],
        })
        print(f"  set price ({target})")
    return iap_id


# --------------------------------------------------------------- metadata

def get_or_create_version(version_string="1.0.0"):
    existing = request("GET", f"/v1/apps/{APP_ID}/appStoreVersions", params={"limit": 5})
    # First: try exact match.
    for v in existing.get("data", []):
        if v["attributes"]["versionString"] == version_string:
            print(f"Reusing version {version_string}: {v['id']} (state={v['attributes']['appStoreState']})")
            return v["id"]
    # Second: reuse any editable draft regardless of version string (e.g. "1.0" vs "1.0.0").
    for v in existing.get("data", []):
        state = v["attributes"]["appStoreState"]
        if state in {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}:
            print(f"Reusing editable version {v['attributes']['versionString']}: {v['id']} (state={state})")
            return v["id"]
    body = {
        "data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version_string},
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
        }
    }
    resp = request("POST", "/v1/appStoreVersions", body)
    print(f"Created version {version_string}: {resp['data']['id']}")
    return resp["data"]["id"]


def cmd_metadata():
    version_id = get_or_create_version()
    # Look for existing en-US localization
    locs = request("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
                   params={"limit": 50})
    en = next((l for l in locs.get("data", []) if l["attributes"]["locale"] == "en-US"), None)

    attrs = {
        "description": (
            "SleepWindow helps you plan sleep timing around 90-minute sleep cycles.\n\n"
            "Pick a wake time and see when to go to bed — or tap \"sleep now\" to see when to set your alarm. "
            "Plan naps that end at the right stage. See a conservative caffeine cutoff for your target bedtime.\n\n"
            "Features\n"
            "• Bedtime calculator — pick your wake time, get ideal bedtime options\n"
            "• Wake-time calculator — tap \"if I fall asleep now,\" get wake options\n"
            "• Nap planner — power nap, short nap, full-cycle nap\n"
            "• Caffeine cutoff — plan when to stop caffeine based on bedtime\n"
            "• Bedtime reminders — simple, reliable local reminders\n"
            "• Saved presets — quick access for workdays and weekends\n"
            "• 12-hour or 24-hour time, light or dark mode\n\n"
            "Privacy-first\n"
            "• No account, no sign-in\n"
            "• No cloud sync, no analytics SDKs\n"
            "• Works fully offline\n\n"
            "One-time purchase\n"
            "• Free: bedtime calculator, limited wake-time calculations, one reminder\n"
            "• Lifetime unlock: everything, forever — no subscriptions, no recurring charges\n\n"
            "Results are estimates for planning sleep timing. SleepWindow is not a medical device and does not diagnose, treat, or monitor any condition."
        ),
        "keywords": "sleep,bedtime,nap,wake,alarm,sleep cycle,caffeine,reminder,bedtime planner,sleep schedule",
        "marketingUrl": "https://has-deploy.github.io/sleepwindow/",
        "promotionalText": "Plan bedtime, wake time, and naps around 90-minute sleep cycles. One-time purchase unlocks everything — no subscriptions.",
        "supportUrl": "https://has-deploy.github.io/sleepwindow/support.html",
    }

    if en:
        print(f"Updating en-US localization {en['id']} ...")
        request("PATCH", f"/v1/appStoreVersionLocalizations/{en['id']}", {
            "data": {"type": "appStoreVersionLocalizations", "id": en["id"], "attributes": attrs}
        })
    else:
        print("Creating en-US localization ...")
        request("POST", "/v1/appStoreVersionLocalizations", {
            "data": {
                "type": "appStoreVersionLocalizations",
                "attributes": {"locale": "en-US", **attrs},
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
            }
        })
    print("Metadata saved.")


def cmd_privacy(url="https://has-deploy.github.io/sleepwindow/privacy.html"):
    """Set the privacy policy URL on app info localization."""
    infos = request("GET", f"/v1/apps/{APP_ID}/appInfos", params={"limit": 10})
    # Use the editable one (state EDITABLE / PREPARE_FOR_SUBMISSION etc.)
    info = infos["data"][0]
    info_id = info["id"]
    locs = request("GET", f"/v1/appInfos/{info_id}/appInfoLocalizations", params={"limit": 20})
    en = next((l for l in locs.get("data", []) if l["attributes"]["locale"] == "en-US"), None)
    if en:
        request("PATCH", f"/v1/appInfoLocalizations/{en['id']}", {
            "data": {
                "type": "appInfoLocalizations",
                "id": en["id"],
                "attributes": {"privacyPolicyUrl": url, "privacyPolicyText": None},
            }
        })
    else:
        request("POST", "/v1/appInfoLocalizations", {
            "data": {
                "type": "appInfoLocalizations",
                "attributes": {"locale": "en-US", "privacyPolicyUrl": url, "name": "SleepWindow"},
                "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info_id}}},
            }
        })
    print(f"Privacy policy URL set to {url}")


# --------------------------------------------------------------- screenshots

SCREENSHOT_DISPLAY_TYPE = "APP_IPHONE_67"  # 6.9" iPhone Pro Max — Apple's required size
IPAD_DISPLAY_TYPE = "APP_IPAD_PRO_3GEN_129"  # 12.9" iPad Pro — Apple's required iPad size


def upload_asset(upload_ops, data: bytes):
    """Upload a single file according to ASC's upload operations array."""
    for op in upload_ops:
        url = op["url"]
        method = op["method"]
        offset = op.get("offset", 0)
        length = op.get("length", len(data))
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        chunk = data[offset:offset + length]
        req = urllib.request.Request(url, data=chunk, method=method, headers=headers)
        urllib.request.urlopen(req).read()


def _upload_screenshots_for(display_type, folder_name):
    version_id = get_or_create_version()
    localizations = request("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    en = next((l for l in localizations["data"] if l["attributes"]["locale"] == "en-US"), None)
    if not en:
        print("Create the en-US localization first with: asc_driver.py metadata")
        return
    loc_id = en["id"]

    sets = request("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets",
                   params={"filter[screenshotDisplayType]": display_type})
    if sets.get("data"):
        set_id = sets["data"][0]["id"]
    else:
        resp = request("POST", "/v1/appScreenshotSets", {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}},
            }
        })
        set_id = resp["data"]["id"]
    print(f"Screenshot set {display_type}: {set_id}")

    folder = pathlib.Path(folder_name)
    files = sorted(folder.glob("*.png"))
    if not files:
        print(f"No screenshots in {folder_name}/")
        return

    for path in files:
        data = path.read_bytes()
        print(f"Uploading {path.name} ({len(data)} bytes) ...")
        resp = request("POST", "/v1/appScreenshots", {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": path.name, "fileSize": len(data)},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
            }
        })
        shot = resp["data"]
        shot_id = shot["id"]
        ops = shot["attributes"]["uploadOperations"]
        upload_asset(ops, data)
        request("PATCH", f"/v1/appScreenshots/{shot_id}", {
            "data": {
                "type": "appScreenshots",
                "id": shot_id,
                "attributes": {"uploaded": True, "sourceFileChecksum": None},
            }
        })
        print(f"  -> {shot_id}")


def cmd_screenshots():
    _upload_screenshots_for(SCREENSHOT_DISPLAY_TYPE, "docs/screenshots/iphone-69")


def cmd_screenshots_ipad():
    _upload_screenshots_for(IPAD_DISPLAY_TYPE, "docs/screenshots/ipad-13")


# --------------------------------------------------------------- status

def cmd_status():
    app = request("GET", f"/v1/apps/{APP_ID}")["data"]
    print(f"App: {app['attributes']['name']}  bundle={app['attributes']['bundleId']}  id={APP_ID}")
    versions = request("GET", f"/v1/apps/{APP_ID}/appStoreVersions", params={"limit": 5})
    for v in versions.get("data", []):
        print(f"  version {v['attributes']['versionString']} state={v['attributes']['appStoreState']} id={v['id']}")
    iaps = request("GET", f"/v1/apps/{APP_ID}/inAppPurchasesV2")
    for iap in iaps.get("data", []):
        print(f"  IAP {iap['attributes']['productId']} state={iap['attributes']['state']}")


# --------------------------------------------------------------- main

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    fn = globals().get(f"cmd_{cmd}")
    if not fn:
        print(f"unknown command: {cmd}", file=sys.stderr)
        print(f"available: iap metadata screenshots privacy status", file=sys.stderr)
        sys.exit(2)
    fn(*sys.argv[2:])
