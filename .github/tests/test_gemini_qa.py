"""Security and error-path tests for Gemini GitHub issue integration."""
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "gemini_qa.py"
spec = importlib.util.spec_from_file_location("gemini_qa", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class GeminiTests(unittest.TestCase):
    def test_source_allowlist(self):
        self.assertTrue(module.is_safe_source("lib/main.dart"))
        self.assertTrue(module.is_safe_source("cloudflare-order-gateway/src/index.ts"))
        self.assertTrue(module.is_safe_source("firestore.rules"))
        for path in (".github/workflows/deploy.yml", "android/app/google-services.json",
                     "lib/private_key.dart", "README.md", "cloudflare-order-gateway/.env"):
            self.assertFalse(module.is_safe_source(path))

    def run_case(self, api_key, response=None, error=None):
        with tempfile.TemporaryDirectory() as tmp:
            event = Path(tmp) / "event.json"
            event.write_text(json.dumps({"issue": {"title": "[Gemini] pricing", "body": ""}}))
            env = {"EVENT_PATH": str(event), "EVENT_NAME": "issues",
                   "ISSUE_NUMBER": "123", "GH_REPO": "owner/repo",
                   "GEMINI_API_KEY": api_key}
            messages = []
            def fake_urlopen(req, timeout=0):
                if error:
                    raise error
                data = ({"models": [{"name": "models/gemini-2.5-flash",
                                     "supportedGenerationMethods": ["generateContent"]}]}
                        if req.full_url.endswith("/models") else response)
                class Reply:
                    def __enter__(self): return self
                    def __exit__(self, *args): return False
                    def read(self): return json.dumps(data).encode()
                return Reply()
            with patch.dict(os.environ, env), patch.object(module, "ROOT", Path(tmp)), \
                 patch.object(module, "post_comment", side_effect=messages.append), \
                 patch.object(module.urllib.request, "urlopen", side_effect=fake_urlopen):
                module.main()
            return messages[0]

    def test_success(self):
        msg = self.run_case("dummy", {"candidates": [{"content": {"parts": [{"text": "OK"}]}}]})
        self.assertIn("OK", msg)

    def test_fallback_after_model_404(self):
        with tempfile.TemporaryDirectory() as tmp:
            event = Path(tmp) / "event.json"
            event.write_text(json.dumps({"issue": {"title": "[Gemini] pricing", "body": ""}}))
            env = {"EVENT_PATH": str(event), "EVENT_NAME": "issues",
                   "ISSUE_NUMBER": "123", "GH_REPO": "owner/repo",
                   "GEMINI_API_KEY": "dummy"}
            messages = []
            attempts = []
            def fake_urlopen(req, timeout=0):
                url = req.full_url
                attempts.append(url)
                if url.endswith("/models"):
                    data = {"models": [
                        {"name": "models/gemini-2.5-flash", "supportedGenerationMethods": ["generateContent"]},
                        {"name": "models/gemini-2.5-flash-lite", "supportedGenerationMethods": ["generateContent"]}]}
                elif "gemini-2.5-flash:" in url:
                    raise HTTPError(url, 404, "Not found", {}, None)
                else:
                    data = {"candidates": [{"content": {"parts": [{"text": "fallback worked"}]}}]}
                class Reply:
                    def __enter__(self): return self
                    def __exit__(self, *args): return False
                    def read(self): return json.dumps(data).encode()
                return Reply()
            with patch.dict(os.environ, env), patch.object(module, "ROOT", Path(tmp)), \
                 patch.object(module, "post_comment", side_effect=messages.append), \
                 patch.object(module.urllib.request, "urlopen", side_effect=fake_urlopen):
                module.main()
            self.assertIn("fallback worked", messages[0])
            self.assertEqual(len(attempts), 3)

    def test_transient_429_retries_once_then_succeeds(self):
        attempts = []
        def opener(req, timeout=0):
            attempts.append(timeout)
            if len(attempts) == 1:
                raise HTTPError(req.full_url, 429, "Rate limit", {}, None)
            class Reply:
                def __enter__(self): return self
                def __exit__(self, *args): return False
                def read(self): return b'{"candidates": []}'
            return Reply()
        request = module.urllib.request.Request("https://example.invalid")
        sleeps = []
        self.assertEqual(module.generate_with_retry(request, opener=opener, sleeper=sleeps.append), {"candidates": []})
        self.assertEqual(len(attempts), 2)
        self.assertEqual(sleeps, [2])

    def test_persistent_429_stops_after_two_attempts(self):
        attempts = []
        def opener(req, timeout=0):
            attempts.append(1)
            raise HTTPError(req.full_url, 429, "Rate limit", {}, None)
        request = module.urllib.request.Request("https://example.invalid")
        with self.assertRaises(HTTPError):
            module.generate_with_retry(request, opener=opener, sleeper=lambda _: None)
        self.assertEqual(len(attempts), 2)

    def test_401_never_retries(self):
        attempts = []
        def opener(req, timeout=0):
            attempts.append(1)
            raise HTTPError(req.full_url, 401, "Unauthorized", {}, None)
        request = module.urllib.request.Request("https://example.invalid")
        with self.assertRaises(HTTPError):
            module.generate_with_retry(request, opener=opener, sleeper=lambda _: None)
        self.assertEqual(len(attempts), 1)

    def test_missing_key(self):
        self.assertIn("GEMINI_API_KEY", self.run_case(""))

    def test_unauthorized(self):
        err = HTTPError("https://example.invalid", 401, "Unauthorized", {}, None)
        self.assertIn("401", self.run_case("dummy", error=err))

    def test_quota(self):
        err = HTTPError("https://example.invalid", 429, "Rate limit", {}, None)
        self.assertIn("429", self.run_case("dummy", error=err))


if __name__ == "__main__":
    unittest.main()
