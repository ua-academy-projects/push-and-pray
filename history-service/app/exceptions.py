class PersistenceError(Exception):
    """Raised when a weather upsert or sync record write fails and has been rolled back."""
