"""Offline container smoke check: non-root Chromium with sandbox required."""
import os

from playwright.sync_api import sync_playwright


def main() -> None:
    if os.getuid() == 0:
        raise RuntimeError('Run the query container as UID 10001, not root')
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, chromium_sandbox=True)
        try:
            page = browser.new_page()
            page.set_content('<title>sandbox-check</title>')
            assert page.title() == 'sandbox-check'
        finally:
            browser.close()
    print('Non-root Chromium sandbox launch succeeded (offline)')


if __name__ == '__main__':
    main()
