const express=require('express'); const request=require('supertest');
const getRealIp=(req)=>req.ip||'unknown';
const app=express(); app.set('trust proxy',1);
app.get('/',(req,res)=>res.json({ip:getRealIp(req)}));
(async()=>{
  const r=await request(app).get('/').set('X-Forwarded-For','9.9.9.9, 203.0.113.7');
  console.log('XFF "9.9.9.9, 203.0.113.7" (9.9.9.9 forjada) => getRealIp:', r.body.ip,
    r.body.ip==='203.0.113.7'?'  ✅ IP real del proxy, ignora la falsa':'  ❌');
})();
