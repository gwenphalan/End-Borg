"""Exercise actual QtQml controllers without QtQuick windows or a compositor."""
from pathlib import Path
import json
import pytest
QtCore=pytest.importorskip('PySide6.QtCore')
QtQml=pytest.importorskip('PySide6.QtQml')
from ..definition import load_definition

ROOT=Path(__file__).resolve().parents[3]
COMPONENTS=ROOT/'modules/common/tool_app'


@pytest.fixture(scope='module')
def engine():
    app=QtCore.QCoreApplication.instance() or QtCore.QCoreApplication([])
    engine=QtQml.QQmlEngine()
    yield engine
    del engine


def create(engine,name):
    component=QtQml.QQmlComponent(engine,QtCore.QUrl.fromLocalFile(str(COMPONENTS/name)))
    assert not component.isError(),[e.toString() for e in component.errors()]
    obj=component.create();assert obj is not None,[e.toString() for e in component.errors()]
    return component,obj


def expression(engine,obj,source):
    call=QtQml.QQmlExpression(engine.rootContext(),obj,source)
    result=call.evaluate()
    assert not call.hasError(),call.error().toString()
    return result[0] if isinstance(result,tuple) else result


def test_action_gating_handler_dispatch_and_backend_signals(engine):
    component,obj=create(engine,'ToolActionController.qml')
    definition=load_definition(COMPONENTS/'examples/starter/app.yaml')
    obj.setProperty('definition',definition)
    assert expression(engine,obj,'enabledFor("save")') is False
    assert expression(engine,obj,'visibleFor("confirm")') is False
    expression(engine,obj,'state=({hasDocument:true,hasSelection:true,mode:"edit"})')
    assert expression(engine,obj,'enabledFor("save")') is True
    assert expression(engine,obj,'checkedFor("edit")') is True
    assert expression(engine,obj,'checkedFor("draw")') is False
    events=[];obj.backendRequested.connect(lambda *args:events.append(args))
    assert expression(engine,obj,'invoke("process", {count:4})') is True
    assert events[0][:2]==('worker','process')
    assert events[0][2]['count']==4
    failures=[];obj.failed.connect(lambda *args:failures.append(args))
    assert expression(engine,obj,'invoke("save")') is False
    assert 'Unregistered' in failures[0][1]
    expression(engine,obj,'handlers=({saveDocument:function(args){return args.allow!==false;}})')
    assert expression(engine,obj,'invoke("save")') is True
    assert expression(engine,obj,'invoke("save",{allow:false})') is False
    expression(engine,obj,'state=({hasDocument:true,busy:true})')
    assert expression(engine,obj,'invoke("save")') is False
    obj.deleteLater();engine.collectGarbage()


def test_transactional_setting_drafts_validation_and_acknowledgement(engine):
    component,obj=create(engine,'ToolSettingsStore.qml')
    obj.setProperty('definition',load_definition(COMPONENTS/'examples/starter/app.yaml'))
    expression(engine,obj,'begin({})')
    assert expression(engine,obj,'get("processing.amount")')==1
    assert expression(engine,obj,'dirty') is False
    assert expression(engine,obj,'write("processing.amount",11)') is False
    assert expression(engine,obj,'valid') is False
    assert expression(engine,obj,'get("processing.amount")')==1
    assert expression(engine,obj,'write("processing.amount",2)') is True
    assert expression(engine,obj,'dirty') is True
    assert expression(engine,obj,'write("unknown",2)') is False
    assert expression(engine,obj,'apply()') is True
    assert expression(engine,obj,'dirty') is True # not committed until host confirms
    expression(engine,obj,'commit()')
    assert expression(engine,obj,'dirty') is False
    expression(engine,obj,'write("processing.amount",3);discard()')
    assert expression(engine,obj,'get("processing.amount")')==2
    obj.deleteLater();engine.collectGarbage()


def test_failed_settings_apply_can_retry_without_committing_or_losing_raw_errors(engine):
    component,obj=create(engine,'ToolSettingsStore.qml')
    obj.setProperty('definition',load_definition(COMPONENTS/'examples/starter/app.yaml'))
    expression(engine,obj,'begin({});write("processing.amount",2)')
    assert expression(engine,obj,'apply()') is True
    expression(engine,obj,'invalid("_application","Storage unavailable")')
    assert expression(engine,obj,'valid') is False
    assert expression(engine,obj,'apply()') is True
    assert expression(engine,obj,'dirty') is True
    assert expression(engine,obj,'committed["processing.amount"]')==1
    expression(engine,obj,'invalid("processing.amount","Incomplete numeric input")')
    assert expression(engine,obj,'apply()') is False
    assert expression(engine,obj,'write("processing.amount",3);apply()') is True
    assert expression(engine,obj,'committed["processing.amount"]')==1
    expression(engine,obj,'commit()')
    assert expression(engine,obj,'dirty') is False
    assert expression(engine,obj,'committed["processing.amount"]')==3
    obj.deleteLater();engine.collectGarbage()


def test_action_setting_predicates_shortcut_gate_and_handler_failure(engine):
    component,obj=create(engine,'ToolActionController.qml')
    expression(engine,obj,'''definition=({state:{ready:true},actions:{
        edit:{visibleWhen:true,enabledWhen:{all:["ready","settings.custom"]},checkedWhen:"settings.custom",target:{kind:"qml",handler:"edit"}}
    }});handlers=({edit:function(){return true;}});settingsValues=({custom:false})''')
    assert expression(engine,obj,'enabledFor("edit")') is False
    assert expression(engine,obj,'invoke("edit",{}, {ready:true,"settings.custom":true})') is True
    assert expression(engine,obj,'settingsValues=({custom:true});checkedFor("edit")') is True
    assert expression(engine,obj,'shortcutsEnabled=false;invokeShortcut("edit")') is False
    assert expression(engine,obj,'invoke("edit")') is True
    failures=[];obj.failed.connect(lambda *args:failures.append(args))
    expression(engine,obj,'handlers=({edit:function(){throw new Error("Rejected edit");}})')
    assert expression(engine,obj,'invoke("edit")') is False
    assert failures[0][0]=='edit' and 'Rejected edit' in failures[0][1]
    assert expression(engine,obj,'enabled=false;invoke("edit")') is False
    obj.deleteLater();engine.collectGarbage()


def test_dirty_action_predicates_follow_document_and_setting_state(engine):
    component,obj=create(engine,'ToolActionController.qml')
    expression(engine,obj,'definition=({actions:{save:{dirtyWhen:"dirty"},clean:{dirtyWhen:false},setting:{dirtyWhen:{eq:["settings.mode","changed"]}},combined:{dirtyWhen:{all:["dirty",{not:"busy"}]}}}})')
    assert expression(engine,obj,'dirtyFor("save")') is False
    expression(engine,obj,'state=({dirty:true,busy:false})')
    assert expression(engine,obj,'dirtyFor("save")') is True
    assert expression(engine,obj,'dirtyFor("combined")') is True
    assert expression(engine,obj,'dirtyFor("clean")') is False
    assert expression(engine,obj,'dirtyFor("missing")') is False
    assert expression(engine,obj,'dirtyFor("save",{dirty:false})') is False
    expression(engine,obj,'settingsValues=({mode:"changed"})')
    assert expression(engine,obj,'dirtyFor("setting")') is True
    expression(engine,obj,'state=({dirty:true,busy:true})')
    assert expression(engine,obj,'dirtyFor("combined")') is False
    obj.deleteLater();engine.collectGarbage()


def test_save_label_width_contract_uses_same_font_and_only_star_reservation():
    label=(COMPONENTS/'ToolActionLabel.qml').read_text()
    button=(COMPONENTS/'ToolSaveButton.qml').read_text()
    assert 'font:root.font' in label
    assert 'root.reserveDirtySpace || root.dirty' in label
    assert 'Layout.preferredWidth:reservedWidth' in label
    assert 'root.iconSize+6+saveLabel.reservedWidth+horizontalPadding*2' in button
    assert 'iconSize:root.iconSize' in button
    assert 'reserveDirtySpace:true' in button
    assert '100' not in button


def test_operation_feedback_suppresses_only_successful_document_saves(engine):
    component,obj=create(engine,'ToolOperationFeedback.qml')
    messages=[];obj.toastRequested.connect(lambda *args:messages.append(args))
    assert expression(engine,obj,'report("save","Saved",false)') is False
    assert expression(engine,obj,'report("save_as","Saved",false)') is False
    assert expression(engine,obj,'report("save","Disk is full",true)') is True
    assert expression(engine,obj,'report("process","Complete",false)') is True
    assert expression(engine,obj,'report("process","",false)') is False
    assert messages==[("Disk is full",True),("Complete",False)]
    expression(engine,obj,'silentSuccessOperations=["write"]')
    assert expression(engine,obj,'report("write","Saved",false)') is False
    obj.deleteLater();engine.collectGarbage()
