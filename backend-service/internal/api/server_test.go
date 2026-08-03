package api

import "testing"

func TestSplitIDsAcceptsKnownInstruments(t *testing.T) {
	ids, ok := splitIDs("crypto:bitcoin:usd,fiat:USD:UAH", 5)
	if !ok || len(ids) != 2 {
		t.Fatalf("expected two known instruments, got %#v, ok=%v", ids, ok)
	}
}

func TestSplitIDsRejectsUnknownInstrument(t *testing.T) {
	if _, ok := splitIDs("crypto:not-in-catalog:usd", 5); ok {
		t.Fatal("unknown instrument must be rejected")
	}
}

func TestCatalogContainsTwentyConfiguredInstruments(t *testing.T) {
	if len(CatalogIDs()) != 20 {
		t.Fatalf("expected 20 configured instruments, got %d", len(CatalogIDs()))
	}
}
