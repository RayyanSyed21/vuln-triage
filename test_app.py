from app import call_local

SAMPLE_ALERT = "CVE-2024-1234: RCE in libfoo < 2.1.0, internet-facing service."


def test_call_local_returns_a_triage_response():
    result = call_local(SAMPLE_ALERT, temp=0.0)
    assert isinstance(result, str)
    assert "SEVERITY" in result.upper()
