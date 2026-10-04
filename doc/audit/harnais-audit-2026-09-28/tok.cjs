const fs=require('fs');const S=__dirname;const u=JSON.parse(fs.readFileSync(S+'/rig_users.json'));
module.exports=async function(i){const r=await fetch('http://localhost:54399/auth/v1/token?grant_type=password',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({email:u[i].email,password:u[i].password})});return (await r.json()).access_token;}
