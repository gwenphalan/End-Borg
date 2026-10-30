"""Generate the settings catalog from Config.qml; fail if any declaration is lost."""
from pathlib import Path
import re,json,sys
from settings_metadata import labels as label_overrides, descriptions as description_overrides
ROOT=Path(__file__).resolve().parents[2]
def write_generated(path,content):
 if '--check' in sys.argv:
  assert path.exists() and path.read_text()==content, f'Catalog drift: {path}. Run generate_catalog.py without --check to rebuild.'
 else:path.write_text(content)
src=(ROOT/'modules/common/Config.qml').read_text()
# Tokenize quoted strings and comments before punctuation so their braces never affect nesting.
rx=re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|`(?:\\.|[^`\\])*`|[A-Za-z_]\w*|\d+(?:\.\d+)?|[^\s]')
tokens=[m for m in rx.finditer(src) if not m.group().startswith(('//','/*'))]
start=next(i for i,t in enumerate(tokens) if t.group()=='JsonAdapter')
start=next(i for i in range(start,len(tokens)) if tokens[i].group()=='{')
leaves=[]
def walk(i,prefix):
 i+=1
 while tokens[i].group()!='}':
  if tokens[i].group()!='property':i+=1;continue
  a=i;i+=1;typ=tokens[i].group();i+=1
  if typ=='list':
   assert tokens[i].group()=='<';typ+='<' + tokens[i+1].group() + '>';i+=3
  name=tokens[i].group();i+=1;assert tokens[i].group()==':';i+=1
  path='.'.join(prefix+[name])
  if typ=='JsonObject':
   assert tokens[i].group()=='JsonObject';i+=1;assert tokens[i].group()=='{';i=walk(i,prefix+[name]);continue
  expr=i;depth=0
  while i<len(tokens):
   t=tokens[i].group()
   if depth==0 and t in ['property','}']:break
   if t in ['[','(','{']:depth+=1
   elif t in [']',')','}']:depth-=1
   i+=1
  end=tokens[i-1].end();lineEnd=src.find('\n',end)
  raw=src[tokens[expr].start():end]
  comment=src[end:lineEnd if lineEnd!=-1 else len(src)].strip().removeprefix('//').strip()
  leaves.append(dict(path=path,type=typ,expression=raw,comment=comment))
 return i+1
end=walk(start,[])
assert len(leaves)==len(re.findall(r'property (?:bool|int|real|string|list<[^>]+>) \w+:',src[src.index('JsonAdapter {'):]))

def human(s):
 s=re.sub(r'([a-z0-9])([A-Z])',r'\1 \2',s).replace('_',' ').replace('Props','options')
 words={'ui':'UI','ai':'AI','gps':'GPS','cpu':'CPU','uscs':'US units','osk':'On-screen keyboard','osd':'On-screen display','nsfw':'NSFW','qt':'Qt','rgb':'RGB','weeb':'Anime content'}
 return ' '.join(words.get(w.lower(),w) for w in s.split()).capitalize().replace('Ui','UI').replace('Ai','AI').replace('Gps','GPS').replace('Cpu','CPU')
categories=[
 ('appearance','Appearance','palette','Wallpaper, colors, typography and display comfort'),
 ('desktop','Desktop','wallpaper','Clock and weather widgets'),
 ('bar','Bar & dock','dock_to_bottom','Position, workspaces, utilities and app shortcuts'),
 ('spotlight','Spotlight','search','Launcher, search and workspace overview'),
 ('interface','Interface','dashboard','Notifications, quick controls, sidebars and capture'),
 ('input','Input & gestures','touchpad_mouse','Scrolling, keyboard and shortcuts'),
 ('audio','Audio & power','volume_up','Volume protection, battery and feedback sounds'),
 ('apps','Applications','apps','Default applications for system actions'),
 ('language','Language & time','language','Language, translation, dates and focus timer'),
 ('services','Services','hub','AI, shared weather, image browser and updates'),
 ('home','Home','home','Connection, devices and quick controls'),
 ('sleep','Sleep','bedtime','Schedule, wind down and bedtime delays'),
 ('privacy','Privacy & security','shield','Lock screen, content policies and work safety'),
 ('advanced','Advanced','tune','Compatibility settings'),
 ('about','About','info','System information and support')]
roots={
 'appearance':'appearance','windows':'appearance','background':'desktop','overview':'spotlight','wallpaperSelector':'desktop',
 'bar':'bar','dock':'bar','tray':'bar', 'sidebar':'interface','notifications':'interface','overlay':'interface','crosshair':'interface','osd':'interface','regionSelector':'interface',
 'interactions':'input','cheatsheet':'input','osk':'input', 'audio':'audio','battery':'audio','light':'audio','sounds':'audio','media':'audio',
 'apps':'apps','launcher':'spotlight','search':'spotlight', 'language':'language','calendar':'language','time':'language',
 'ai':'services','borgIntelligence':'services','networking':'services','resources':'services','musicRecognition':'services','updates':'services','screenRecord':'services','screenSnip':'services',
 'musicAssistant':'home','homeAssistant':'home','lock':'privacy','policies':'privacy','workSafety':'privacy','conflictKiller':'advanced','hacks':'advanced'}
group_names={
 'appearance':'Style','appearance.fonts':'Fonts','appearance.transparency':'Transparency','appearance.wallpaperTheming':'Application themes','appearance.palette':'Colors','windows':'App windows',
 'background':'Wallpaper','background.widgets.clock':'Clock widget','background.widgets.clock.cookie':'Analog clock','background.widgets.clock.digital':'Digital clock','background.widgets.clock.quote':'Clock quote','background.widgets.weather':'Weather widget','background.parallax':'Parallax','overview':'Workspace overview','wallpaperSelector':'Wallpaper picker',
 'bar':'Position & style','bar.autoHide':'Auto-hide','bar.resources':'Resource indicators','bar.utilButtons':'Utility buttons','bar.workspaces':'Workspaces','bar.weather':'Weather','bar.indicators':'Indicators','bar.tooltips':'Tooltips','dock':'Dock','tray':'System tray',
 'sidebar':'Sidebars','sidebar.quickToggles':'Quick toggles','sidebar.quickSliders':'Quick sliders','sidebar.cornerOpen':'Corner gestures','sidebar.translator':'Translator','sidebar.ai':'AI sidebar','sidebar.booru':'Image browser',
 'notifications':'Notifications','osd':'On-screen display','overlay':'Overlay','overlay.floatingImage':'Floating image','crosshair':'Crosshair','regionSelector':'Screen selection','regionSelector.targetRegions':'Selection hints','regionSelector.rect':'Rectangle selection','regionSelector.circle':'Circle selection','regionSelector.annotation':'Annotations',
 'interactions.scrolling':'Scrolling','interactions.deadPixelWorkaround':'Edge interactions','cheatsheet':'Shortcut guide','osk':'On-screen keyboard',
 'audio.protection':'Volume protection','battery':'Battery','light.night':'Night light','light.antiFlashbang':'Brightness protection','sounds':'Sounds','media':'Media players',
 'apps':'Apps for system actions','launcher':'Launcher','search':'Search behavior','search.prefix':'Search prefixes','search.imageSearch':'Image search',
 'language':'Interface language','language.translator':'Translation','calendar':'Calendar','time':'Clock & date','time.pomodoro':'Focus timer',
 'ai':'AI models','borgIntelligence':'Borg intelligence','networking':'Networking','resources':'Resources','musicRecognition':'Music recognition','updates':'Updates','screenRecord':'Screen recording','screenSnip':'Screenshots',
 'homeAssistant':'Connection','lock':'Lock screen','lock.blur':'Lock blur','lock.security':'Lock security','policies':'Content policies','workSafety.enable':'Work safety','workSafety.triggerCondition':'Work safety rules','conflictKiller':'Service conflicts','hacks':'Compatibility'}
labels={
 'homeAssistant.enabled':'Enable Home Assistant','homeAssistant.url':'Server address','homeAssistant.credentialRevision':'Credential revision','homeAssistant.homeColumns':'Maximum tile columns','homeAssistant.quickToggleEntities':'Sidebar device shortcuts','homeAssistant.barControlEntities':'Top-bar device shortcuts','homeAssistant.hiddenEntities':'Hidden devices','homeAssistant.favoriteEntities':'Favorite devices',
 'bar.bottom':'Place bar on bottom or right','bar.vertical':'Vertical bar','bar.verbose':'Show full bar controls','bar.cornerStyle':'Bar shape','bar.screenList':'Visible on displays','appearance.fakeScreenRounding':'Screen corner rounding','appearance.extraBackgroundTint':'Wallpaper tint','appearance.palette.type':'Color scheme','language.ui':'Interface language','policies.weeb':'Anime content','policies.ai':'AI access','ai.extraModels':'Custom AI models','apps.terminal':'Terminal command','sidebar.quickToggles.android.toggles':'Quick-toggle layout','time.pomodoro.focus':'Focus duration','bar.weather.useUSCS':'Use US weather units','bar.weather.enableGPS':'Use location service','battery.full':'Full battery notification threshold'}
enums={
 'policies.ai':[(0,'Disabled'),(1,'Allowed'),(2,'Local only')],'policies.weeb':[(0,'Disabled'),(1,'Allowed'),(2,'Private')],
 'appearance.fakeScreenRounding':[(0,'Off'),(1,'Always'),(2,'Outside fullscreen')],'bar.cornerStyle':[(0,'Hug'),(1,'Float'),(2,'Rectangle')],
 'ai.tool':[('functions','Functions'),('search','Search'),('none','None')],
 'appearance.palette.type':[(s,human(s.removeprefix('scheme-'))) for s in ['auto','scheme-content','scheme-expressive','scheme-fidelity','scheme-fruit-salad','scheme-monochrome','scheme-neutral','scheme-rainbow','scheme-tonal-spot']],
 'sidebar.quickToggles.style':[('android','Android'),('classic','Classic')],
 'sidebar.booru.defaultProvider':[('yandere','Yande.re'),('konachan','Konachan'),('gelbooru','Gelbooru'),('zerochan','Zerochan')],
 'time.format':[('hh:mm','24 hr'),('h:mm ap','12 hr am/pm'),('h:mm AP','12 hr AM/PM')],
}
# Conditions disable only subordinate settings; stored values remain intact.
conditions={'appearance.transparency':['appearance.transparency.enable'], 'audio.protection':['audio.protection.enable'], 'bar.autoHide':['bar.autoHide.enable'], 'bar.weather':['bar.weather.enable'], 'dock':['dock.enable'], 'lock.blur':['lock.blur.enable'], 'sidebar.quickSliders':['sidebar.quickSliders.enable'], 'sidebar.cornerOpen':['sidebar.cornerOpen.enable'], 'sidebar.translator':['sidebar.translator.enable'], 'background.widgets.clock':['background.widgets.clock.enable'], 'background.widgets.weather':['background.widgets.weather.enable'], 'background.widgets.clock.quote':['background.widgets.clock.quote.enable'], 'notifications.monitor':['notifications.monitor.enable']}
for e in leaves:
 path=e['path'];parts=path.split('.');e['category']=roots[parts[0]]
 group=max((g for g in group_names if path==g or path.startswith(g+'.')),key=len,default=parts[0])
 if path.startswith('homeAssistant.'):
  leaf=parts[-1]
  group='homeAssistant.' + ('devices' if leaf in ['hiddenEntities','favoriteEntities','quickToggleEntities','barControlEntities'] else 'layout' if leaf in ['showMediaPlayers','showBarControls','showBarHomeButton','suggestQuickControls','quickControlLimit','barControlLimit','homeColumns'] else 'rooms' if leaf in ['rememberArea','defaultAreaId'] else 'connection')
  group_names.update({'homeAssistant.devices':'Devices & shortcuts','homeAssistant.layout':'Controls & layout','homeAssistant.rooms':'Rooms','homeAssistant.connection':'Connection'})
 e['group']=group;e['groupTitle']=group_names.get(group,human(group.split('.')[-1]))
 label=label_overrides.get(path,labels.get(path,human(parts[-1])))
 if parts[-1] in ['enable','enabled']:label='Enable '+human(parts[-2]).lower()
 if path in labels:label=labels[path]
 if path in label_overrides:label=label_overrides[path]
 e['label']=label
 comment=e.pop('comment');e.pop('expression')
 e['description']=comment if comment and not comment.startswith(('Options','Allowed','0:','"')) else ''
 e['description']=description_overrides.get(path,e['description'])
 if path in enums:e['choices']=[{'value':v,'name':n} for v,n in enums[path]]
 elif e['type']=='string':
  quoted=re.findall(r'"([\w-]+)"',comment)
  if len(quoted)>=2 and ('Options' in comment or 'Options' in src[max(0,src.find('property string '+parts[-1]+':')-10):src.find('property string '+parts[-1]+':')+200] or 'placementStrategy' in path):
   e['choices']=[{'value':v,'name':human(v)} for v in dict.fromkeys(quoted)]
 e['multiline']=path in ['ai.systemPrompt','background.widgets.clock.quote.text']
 e['readOnly']=path in ['homeAssistant.credentialRevision','musicAssistant.credentialRevision']
 if e['readOnly']:e['description']='Managed when credentials change. Tokens are stored in the desktop keyring.'
 e['conditions']=[c for prefix,cs in conditions.items() if path.startswith(prefix+'.') for c in cs if c!=path]
 if e['type'] in ['int','real']:
  e['min']=0;e['max']=1000000;e['step']=1 if e['type']=='int' else .05
  if any(x in path.lower() for x in ['opacity','transparency','harmony','termfgboost']):e.update(min=0,max=1,step=.05)
  if path.endswith(('.x','.y')):e.update(min=-100000,max=100000)
  if path.endswith(('Threshold','battery.low','battery.critical','battery.suspend')):e['max']=100
  if path=='battery.full':e['max']=101
  if path=='light.night.colorTemperature':e.update(min=1000,max=10000,step=100)
  if path.endswith('.font.weight'):e.update(min=1,max=1000,step=25)
  if path.endswith('.font.width'):e.update(min=25,max=200,step=5)
  if path.endswith('.font.size'):e.update(min=48,max=400,step=1)
  if path.endswith('.font.roundness'):e.update(min=0,max=100,step=1)
  if path.endswith('.font.letterSpacing'):e.update(min=0,max=.5,step=.005,unit='em')
  if path=='musicAssistant.pageSize':e.update(min=10,max=200)
  if path=='borgIntelligence.timeoutSeconds':e.update(min=5,max=210)
  if path=='homeAssistant.homeColumns':e.update(min=1,max=3)
  if path in ['homeAssistant.quickControlLimit','homeAssistant.barControlLimit']:e.update(min=1,max=12)
  if path=='time.pomodoro.cyclesBeforeLongBreak':e['min']=1
  if path.endswith(('columns','rows','historyLength','shown','updateInterval','fetchInterval','checkInterval')):e['min']=1
  if path in ['overview.scale','overlay.clickthroughOpacity']:e.update(min=.01,max=1,step=.01)
 if path!='time.pomodoro.cyclesBeforeLongBreak' and (path.endswith(('Interval','Delay','timeout','delay','Duration','breakTime','longBreak','.focus')) or path.startswith('time.pomodoro.')):
  e['unit']='seconds' if path.startswith('time.pomodoro.') and not path.endswith('cyclesBeforeLongBreak') else 'minutes' if path.endswith(('fetchInterval','checkInterval')) else 'seconds' if path.startswith('musicRecognition.') else 'ms' if e['type'] in ['int','real'] else ''
 # These are count properties even though legacy Config stores them as real.
 if path in ['overview.rows','overview.columns']:e.update(type='int',min=1,step=1)
 # Audio clamps real volume to hardMaxValue=2.00 in services/Audio.qml.
 if path in ['audio.protection.maxAllowedIncrease','audio.protection.maxAllowed']:e.update(min=0,max=200,step=1,unit='%')
 if path in ['battery.low','battery.critical','battery.full','battery.suspend','bar.resources.memoryWarningThreshold','bar.resources.swapWarningThreshold','bar.resources.cpuWarningThreshold']:e['unit']='%'
 if path=='light.night.colorTemperature':e['unit']='K'
 if path=='borgIntelligence.timeoutSeconds':e['unit']='seconds'
 if path=='background.widgets.clock.digital.font.size':e.pop('max',None) # No artificial font-size ceiling.
 if path.endswith(('savePath','wallpaperPath','thumbnailPath','imageSource')):e['picker']='folder' if path.endswith('savePath') else 'file'
 if path.startswith('appearance.fonts.') or path.endswith('.font.family'):e['picker']='font'
 if path=='appearance.palette.accentColor':e['picker']='color'
 if path=='language.ui':e['dynamicChoices']='language'
 if path=='musicAssistant.defaultPlayerId':e['dynamicChoices']='musicPlayer'
 if path=='homeAssistant.defaultAreaId':e['dynamicChoices']='area'
 if path=='sidebar.quickToggles.android.toggles':e['itemFields']=[{'key':'type','type':'string','choices':['network','bluetooth','idleInhibitor','mic','audio','nightLight','darkMode','notifications','screenSnip','colorPicker','screenRecord','gameMode','onScreenKeyboard','powerProfile','musicRecognition','cloudflareWarp','easyEffects']},{'key':'size','type':'int','min':1,'max':5}]
 if path=='ai.extraModels':e['itemFields']=[{'key':k,'type':'bool' if k=='requires_key' else 'string',**({'choices':['openai','gemini']} if k=='api_format' else {})} for k in ['name','model','endpoint','api_format','description','homepage','icon','key_id','key_get_link','requires_key']]
 if e['type'].startswith('list') and not e['description']:e['description']='Add, edit, remove or reorder entries.'
 if e['type']=='string' and not e.get('choices') and not e.get('dynamicChoices'):e['description']+=' Leave blank to use an empty value.' if path.endswith(('savePath','accentColor')) else ''
# Native actions supplement schema-backed preferences.
cat=[dict(id=i,title=t,icon=ic,description=d) for i,t,ic,d in categories]
out=ROOT/'modules/settings/desktop';out.mkdir(exist_ok=True)
write_generated(out/'settings_schema.js','// Generated by generate_settings_schema.py from Config.qml.\n.pragma library\nvar categories = '+json.dumps(cat,ensure_ascii=False,indent=2)+';\nvar entries = '+json.dumps(leaves,ensure_ascii=False,indent=2)+';\n')
body=src[tokens[start].end():tokens[end-1].start()]
body=re.sub(r'^\s*id: configOptionsJsonAdapter\s*$', '',body,flags=re.M)
write_generated(out/'SettingsDefaults.qml','pragma Singleton\nimport QtQuick\nimport Quickshell\nimport Quickshell.Io\nimport qs.modules.common\n\nSingleton {\n    property JsonObject options: JsonObject {'+body+'\n    }\n}\n')

print(f'{len(leaves)} preferences, {len(set(e["group"] for e in leaves))} subsections, {len(categories)} categories')
