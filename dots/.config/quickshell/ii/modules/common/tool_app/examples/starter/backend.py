"""Reference worker. Start only explicitly; stdout is reserved for protocol messages."""
from pathlib import Path
import sys
for directory in Path(__file__).resolve().parents:
    if (directory/'scripts/tool_app/protocol.py').is_file():
        sys.path.insert(0,str(directory/'scripts'));break
from tool_app.protocol import serve
from tool_app.profile_store import ProfileStore


def main():
    profiles=ProfileStore('tool-app-starter')
    def save(payload):
        document=profiles.save(payload['name'],payload['values'])
        return dict(profile=document,profiles=profiles.list())
    def rename(payload):
        profiles.rename(payload['id'],payload['name']);return dict(profiles=profiles.list())
    def update(payload):
        profiles.update(payload['id'],payload['values']);return dict(profiles=profiles.list())
    def delete(payload):
        profiles.delete(payload['id']);return dict(profiles=profiles.list())
    serve({
        'process':lambda payload:dict(processed=payload.get('count',1)),
        # Replace this acknowledgement with domain validation/persistence.
        'settings.apply':lambda payload:dict(values=payload['values']),
        'profiles.list':lambda payload:dict(profiles=profiles.list()),
        'profiles.read':lambda payload:profiles.read(payload['id']),
        'profiles.save':save,'profiles.rename':rename,'profiles.update':update,'profiles.delete':delete,
    })

if __name__=='__main__':main()
