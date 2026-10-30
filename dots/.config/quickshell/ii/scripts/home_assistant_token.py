"""Read/store HA credentials without requesting a keyring unlock."""
import sys

ATTRIBUTES = {"application": "illogical-impulse-home-assistant"}
LOGIN_COLLECTION = "/org/freedesktop/secrets/collection/login"


class CredentialLocked(Exception):
    pass


def writable_collection(storage, connection):
    # Quickshell's password unlock and PAM unlock this collection at login.
    # An unrelated default collection may remain locked after reboot.
    try:
        return storage.Collection(connection, LOGIN_COLLECTION)
    except storage.exceptions.ItemNotFoundException:
        # Other Secret Service providers may not have a GNOME Login keyring.
        return storage.Collection(connection)


def save_token(storage, token):
    if not token:
        raise ValueError("Empty credential")
    connection = storage.dbus_init()
    try:
        collection = writable_collection(storage, connection)
        if collection.is_locked():
            raise CredentialLocked()
        collection.create_item("illogical-impulse Home Assistant", ATTRIBUTES,
                               token.encode(), replace=True)
    finally:
        connection.close()


def read_token(storage):
    connection = storage.dbus_init()
    try:
        items = list(storage.search_items(connection, ATTRIBUTES))
        # Prefer the login credential over tokens saved by older versions.
        items.sort(key=lambda item: not item.item_path.startswith(LOGIN_COLLECTION + "/"))
        locked = False
        for item in items:
            if not item.is_locked():
                token = item.get_secret().decode().strip()
                if token:
                    return token
            else:
                locked = True
        if locked:
            raise CredentialLocked()
        return ""
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        import secretstorage
        if sys.argv[1:] == ["--store"]:
            save_token(secretstorage, sys.stdin.read().strip())
        elif sys.argv[1:] == ["--migrate"]:
            # Copy an accessible legacy token into the login-unlocked keyring.
            # Keep the old item as a fallback; never print the credential.
            save_token(secretstorage, read_token(secretstorage))
        elif not sys.argv[1:]:
            token = read_token(secretstorage)
            if token:
                print(token)
            sys.exit(0 if token else 1)
        else:
            raise ValueError("Unknown operation")
    except CredentialLocked:
        sys.exit(3)
    except Exception:
        # No secret or D-Bus error text in logs. The service retries after unlock.
        sys.exit(2)
