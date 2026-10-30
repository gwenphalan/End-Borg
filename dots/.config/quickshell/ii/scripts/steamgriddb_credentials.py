"""Private credential bridge: stdin for writes, captured stdout for internal reads."""
import getpass
import os
import sys

from home_assistant_token import CredentialLocked, writable_collection

ATTRIBUTES = {"application": "illogical-impulse-steamgriddb"}


def store(storage, key):
    key = key.strip()
    if not key or len(key) > 512 or any(not 33 <= ord(character) <= 126 for character in key):
        raise ValueError("Invalid credential")
    connection = storage.dbus_init()
    try:
        collection = writable_collection(storage, connection)
        if collection.is_locked():
            raise CredentialLocked()
        collection.create_item("illogical-impulse SteamGridDB", ATTRIBUTES, key.encode(), replace=True)
    finally:
        connection.close()


def read(storage):
    connection = storage.dbus_init()
    try:
        locked = False
        for item in storage.search_items(connection, ATTRIBUTES):
            if item.is_locked():
                locked = True
                continue
            value = item.get_secret().decode().strip()
            if value:
                return value
        if locked:
            raise CredentialLocked()
        return ""
    finally:
        connection.close()


def main():
    try:
        import secretstorage
        if sys.argv[1:] == ["--store"]:
            store(secretstorage, sys.stdin.read(513))
        elif sys.argv[1:] == ["--prompt"]:
            # No echo, command-line credential, temporary file or shell history.
            os.environ["STEAMGRIDDB_API_KEY"] = getpass.getpass("SteamGridDB API key (hidden): ")
            store(secretstorage, os.environ.pop("STEAMGRIDDB_API_KEY"))
            print("SteamGridDB key saved in the desktop keyring.")
        elif sys.argv[1:] == ["--read"]:
            value = read(secretstorage)
            if value:
                sys.stdout.write(value)
            return 0 if value else 1
        else:
            return 2
        return 0
    except CredentialLocked:
        return 3
    except Exception:
        return 2


if __name__ == "__main__":
    sys.exit(main())
