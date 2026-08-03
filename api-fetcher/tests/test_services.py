import time

import pytest

from app.services import TTLCache, RateService


def test_parse_normalizes_instruments():
    assert RateService.parse("crypto:bitcoin:USD") == ("crypto", "bitcoin", "usd")
    assert RateService.parse("fiat:usd:uah") == ("fiat", "USD", "UAH")


@pytest.mark.parametrize("instrument", ["bitcoin", "stock:AAPL:USD", "fiat:US:UAH", "fiat:USD:12"])
def test_parse_rejects_invalid_instrument(instrument):
    with pytest.raises(ValueError):
        RateService.parse(instrument)


def test_ttl_cache_expires():
    cache = TTLCache()
    cache.set("key", "value", 1)
    assert cache.get("key") == "value"
    cache._items["key"] = (time.monotonic() - 1, "value")
    assert cache.get("key") is None
