"""Serialize the pinned official March 2020 model; does not require the original app."""
import pathlib,json,hashlib,re,struct,sys
root=pathlib.Path(__file__).parent
identity=json.loads((root/'official-model-materialization.json').read_text())
source=pathlib.Path(sys.argv[1]).read_bytes()
assert hashlib.sha256(source).hexdigest()==identity['sourceSHA256'], 'Wrong official model source revision'
text=source.decode();arrays={}
for typ,name,body in re.findall(r'(signed char|int)\s+(f\d+_(?:weight|bias))\[[^\]]*\]\s*=\s*\{([^}]*)\}',text):
 values=[int(x) for x in re.findall(r'-?\d+',body)]
 arrays[name]=bytes(x&255 for x in values) if typ=='signed char' else struct.pack('<'+'i'*len(values),*values)
rows=re.findall(r'\{\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*([\d.eE+-]+)f,\s*(f\d+_weight),\s*(f\d+_bias)\}',text)
assert len(rows)==24
output=bytearray(b'EYFC24V1'+struct.pack('<I',24))
for pad,stride,kernel,channels,count,scale,weight,bias in rows:
 output+=struct.pack('<iiiiifII',int(pad),int(stride),int(kernel),int(channels),int(count),float(scale),len(arrays[weight]),len(arrays[bias]))+arrays[weight]+arrays[bias]
assert hashlib.sha256(output).hexdigest()==identity['serializedModelSHA256']
path=pathlib.Path(sys.argv[2]);path.parent.mkdir(parents=True,exist_ok=True)
if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest()!=identity['serializedModelSHA256']:
 temporary=path.with_name(path.name+'.tmp');temporary.write_bytes(output);temporary.replace(path)
print(identity['serializedModelSHA256'])
