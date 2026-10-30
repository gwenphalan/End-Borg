"""Explicit, configurable per-user desktop/MIME/icon registration.

Rendering is read-only. CLI writes only with --apply; refresh/default-association
commands require their separate flags and use argument vectors, never a shell.
"""
from dataclasses import dataclass
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET


@dataclass(frozen=True)
class FileTypeSpec:
    app_id:str
    app_name:str
    command:tuple[str,...]
    mime_type:str
    extensions:tuple[str,...]
    description:str=''
    categories:tuple[str,...]=('Utility',)
    startup_wm_class:str|None=None
    icon_svg:str|None=None
    icon_name:str|None=None


def _text(value):
    if not isinstance(value,str) or any(character in value for character in ('\n','\r','\x00')):
        raise ValueError('Registration fields must be single-line strings.')
    return value


def desktop_command(arguments):
    if not arguments:raise ValueError('An application command is required.')
    values=[]
    for argument in arguments:
        argument=_text(argument)
        if argument in ('%f','%F','%u','%U'):
            values.append(argument)
        else:
            escaped=argument.replace('%','%%').replace('\\','\\\\').replace('"','\\"').replace('`','\\`').replace('$','\\$')
            values.append('"'+escaped+'"')
    return ' '.join(values)


def render(spec):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*',spec.app_id):raise ValueError('Invalid application identifier.')
    if not re.fullmatch(r'[a-z0-9.+-]+/[a-z0-9.+-]+',spec.mime_type):raise ValueError('Invalid MIME type.')
    if not spec.extensions or any(not re.fullmatch(r'\.[A-Za-z0-9][A-Za-z0-9_+-]*',ext) for ext in spec.extensions):
        raise ValueError('File extensions must be simple dotted suffixes.')
    if any(not re.fullmatch(r'[A-Za-z0-9-]+',category) for category in spec.categories):raise ValueError('Invalid desktop category.')
    desktop=['[Desktop Entry]','Type=Application','Name='+_text(spec.app_name)]
    if spec.description:desktop.append('Comment='+_text(spec.description))
    desktop.extend(['Exec='+desktop_command(spec.command),'Terminal=false','Categories='+';'.join(spec.categories)+';',
                    'MimeType='+spec.mime_type+';'])
    icon_name=spec.app_id if spec.icon_svg else spec.icon_name
    if icon_name:desktop.append('Icon='+_text(icon_name))
    if spec.startup_wm_class:desktop.append('StartupWMClass='+_text(spec.startup_wm_class))
    root=ET.Element('mime-info',xmlns='http://www.freedesktop.org/standards/shared-mime-info')
    mime=ET.SubElement(root,'mime-type',type=spec.mime_type)
    ET.SubElement(mime,'comment').text=spec.description or spec.app_name
    for extension in spec.extensions:ET.SubElement(mime,'glob',pattern='*'+extension)
    if icon_name:ET.SubElement(mime,'icon',name=icon_name)
    files={f'applications/{spec.app_id}.desktop':'\n'.join(desktop)+'\n',
           f'mime/packages/{spec.app_id}.xml':ET.tostring(root,encoding='unicode')+'\n'}
    if spec.icon_svg:
        icon=ET.fromstring(spec.icon_svg)
        if icon.tag.split('}')[-1]!='svg':raise ValueError('The icon must be SVG.')
        files[f'icons/hicolor/scalable/apps/{spec.app_id}.svg']=spec.icon_svg
    return files


def install(spec,data_home=None,refresh=False,set_default=False):
    files=render(spec)
    root=Path(data_home) if data_home is not None else Path(os.environ.get('XDG_DATA_HOME',str(Path.home()/'.local/share')))
    written=[]
    for relative,contents in files.items():
        target=root/relative;target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text(contents);written.append(str(target))
    if refresh:
        subprocess.run(['update-desktop-database',str(root/'applications')],check=True)
        subprocess.run(['update-mime-database',str(root/'mime')],check=True)
    if set_default:
        subprocess.run(['xdg-mime','default',spec.app_id+'.desktop',spec.mime_type],check=True)
    return written


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('spec',help='JSON FileTypeSpec document')
    parser.add_argument('--apply',action='store_true')
    parser.add_argument('--data-home')
    parser.add_argument('--refresh',action='store_true')
    parser.add_argument('--set-default',action='store_true')
    args=parser.parse_args()
    value=json.loads(Path(args.spec).read_text())
    for key in ('command','extensions','categories'):
        if key in value:value[key]=tuple(value[key])
    spec=FileTypeSpec(**value)
    if not args.apply and (args.refresh or args.set_default):parser.error('--refresh/--set-default require --apply')
    result=install(spec,args.data_home,args.refresh,args.set_default) if args.apply else render(spec)
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
