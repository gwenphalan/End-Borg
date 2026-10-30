"""Application-namespaced named JSON profiles with stable opaque IDs and atomic writes."""
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import uuid
from .files import atomic_json
from .definition import finite_json


class ProfileStore:
    def __init__(self,namespace,root=None):
        if not isinstance(namespace,str) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_.-]*',namespace):raise ValueError('Invalid profile namespace')
        self.directory=Path(root) if root else Path(os.environ.get('XDG_DATA_HOME',str(Path.home()/'.local/share')))/namespace/'profiles'

    @contextmanager
    def locked(self):
        self.directory.mkdir(parents=True,exist_ok=True)
        with (self.directory/'.lock').open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX)
            try:yield
            finally:fcntl.flock(lock,fcntl.LOCK_UN)

    def filename(self,identifier):
        if not isinstance(identifier,str) or not re.fullmatch(r'[0-9a-f]{32}',identifier):raise ValueError('Invalid profile id')
        return self.directory/(identifier+'.json')

    def read(self,identifier):
        try:
            document=json.loads(self.filename(identifier).read_text())
        except RecursionError as error:
            raise ValueError('Invalid profile document') from error
        if (not isinstance(document,dict) or type(document.get('version')) is not int or document['version']!=1
                or document.get('id')!=identifier or not isinstance(document.get('name'),str)
                or not document['name'].strip() or len(document['name'].strip())>120
                or any(character in document['name'] for character in ('\x00','\n','\r'))
                or 'payload' not in document):
            raise ValueError('Invalid profile document')
        return finite_json(document,'profile')

    def list(self):
        if not self.directory.is_dir():return []
        result=[]
        for filename in self.directory.glob('*.json'):
            try:
                doc=self.read(filename.stem);result.append(dict(id=doc['id'],name=doc['name']))
            except (OSError,ValueError,TypeError):continue
        return sorted(result,key=lambda profile:(profile['name'].casefold(),profile['id']))

    def valid_name(self,name,exclude=None):
        if not isinstance(name,str) or not name.strip() or len(name.strip())>120 or any(character in name for character in ('\x00','\n','\r')):raise ValueError('Enter a name between 1 and 120 characters')
        name=name.strip()
        if any(p['id']!=exclude and p['name'].casefold()==name.casefold() for p in self.list()):raise ValueError('A profile with that name already exists')
        return name

    def save(self,name,payload):
        payload=finite_json(payload,'profile.payload')
        with self.locked():
            name=self.valid_name(name);identifier=uuid.uuid4().hex
            atomic_json(self.filename(identifier),dict(version=1,id=identifier,name=name,payload=payload))
            return self.read(identifier)

    def update(self,identifier,payload):
        payload=finite_json(payload,'profile.payload')
        with self.locked():
            document=self.read(identifier);document['payload']=payload;atomic_json(self.filename(identifier),document)
            return self.read(identifier)

    def rename(self,identifier,name):
        with self.locked():
            document=self.read(identifier);document['name']=self.valid_name(name,identifier);atomic_json(self.filename(identifier),document)
            return self.read(identifier)

    def delete(self,identifier):
        with self.locked():self.filename(identifier).unlink()
