"""Serial JSON-lines worker protocol for ToolBackendProcess.

serve({'operation': callback}) reads {id, op, payload}; callback receives a fresh
finite JSON payload. Each line produces one {id, ok, result|error}. Callback
prints are redirected to stderr. No evaluation or request-controlled imports.
"""
from contextlib import redirect_stdout
import json
import sys
from .definition import finite_json


def response(request,handlers):
    identifier=request.get('id') if isinstance(request,dict) else None
    valid_id=type(identifier) is int and 1<=identifier<=9007199254740991
    identifier=identifier if valid_id else None
    try:
        if not isinstance(request,dict) or not valid_id:
            raise ValueError('Expected a positive safe integer request id.')
        finite_json(request,'request')
        unknown=set(request)-{'id','op','payload'}
        if unknown:raise ValueError('Unknown request fields: '+', '.join(sorted(unknown)))
        operation=request.get('op')
        if not isinstance(handlers,dict) or not isinstance(operation,str) or operation not in handlers:
            raise ValueError('Unknown operation.')
        if not callable(handlers[operation]):raise ValueError('Operation handler is not callable.')
        payload=request.get('payload',{})
        if not isinstance(payload,dict):raise ValueError('Payload must be an object.')
        payload=finite_json(payload,'payload')
        with redirect_stdout(sys.stderr):
            result=handlers[operation](payload)
        return dict(id=identifier,ok=True,result=finite_json(result,'result'))
    except Exception as error:
        return dict(id=identifier,ok=False,error=str(error) or type(error).__name__)


def _constant(value):
    raise ValueError('Non-finite JSON numbers are not supported.')


def _mapping(pairs):
    result={}
    for key,value in pairs:
        if key in result:raise ValueError('Duplicate JSON key: '+key)
        result[key]=value
    return result


def serve(handlers,input_stream=None,output_stream=None):
    source=input_stream if input_stream is not None else sys.stdin
    target=output_stream if output_stream is not None else sys.stdout
    for line in source:
        try:
            request=json.loads(line,parse_constant=_constant,object_pairs_hook=_mapping)
            result=response(request,handlers)
        except (ValueError,TypeError,RecursionError) as error:
            result=dict(id=None,ok=False,error=str(error) or type(error).__name__)
        target.write(json.dumps(result,allow_nan=False)+'\n')
        target.flush()
