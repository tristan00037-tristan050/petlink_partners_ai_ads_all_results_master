const express=require('express');
const q=require('../lib/quality');
const r=express.Router();

r.post('/validate', express.json(), async (req,res)=>{
  const { text, channel } = req.body||{};
  return res.json(q.validate({ text, channel }));
});

r.post('/autofix', express.json(), async (req,res)=>{
  const { text, channel } = req.body||{};
  return res.json(q.autofix({ text, channel }));
});

module.exports=r;
