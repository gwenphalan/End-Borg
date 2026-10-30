function title(value) { return String(value).replace(/_/g," ").replace(/^./,c=>c.toUpperCase()); }
function actions(services,entity) {
    const domain=entity.entity_id.split(".")[0];
    return Object.entries(services[domain] || {}).filter(([key,value]) => value.target !== undefined).map(([key,value]) => ({key:key,name:value.name || title(key),schema:value})).sort((a,b)=>a.name.localeCompare(b.name));
}
function fields(schema) {
    const result=[];
    function visit(items) { for(const [key,value] of Object.entries(items || {})) {
        if(value.fields) visit(value.fields);
        else if(key!=="entity_id") result.push(Object.assign({key:key,name:value.name || title(key)},value));
    } }
    visit(schema?.fields);return result;
}
function payload(fields,values) {
    const result={};
    for(const field of fields) {
        let value=values[field.key];
        if(value===undefined || value==="") {
            if(field.required) throw new Error(field.name+": required");
            continue;
        }
        const selector=field.selector || {};
        if(selector.number) {
            value=Number(value);const n=selector.number;
            if(!Number.isFinite(value) || (n.min!==undefined && value<n.min) || (n.max!==undefined && value>n.max)) throw new Error(field.name+": outside allowed range");
        } else if(selector.boolean!==undefined) value=!!value;
        else if(selector.object!==undefined || selector.color_rgb!==undefined || selector.color_hs!==undefined || selector.select?.multiple || selector.entity?.multiple || selector.target!==undefined) {
            if(typeof value==="string") {try {value=JSON.parse(value);} catch(e){throw new Error(field.name+": enter valid JSON");}}
            if((selector.color_rgb!==undefined || selector.color_hs!==undefined || selector.select?.multiple || selector.entity?.multiple) && !Array.isArray(value)) throw new Error(field.name+": enter a list");
        }
        result[field.key]=value;
    }
    return result;
}
