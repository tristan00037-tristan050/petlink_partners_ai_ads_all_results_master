const express=require("express"); const path=require("path"); const r=express.Router();

// HTML 파일은 공개 (인증은 내부 API 호출 시에만)
r.get("/ui/login", (req,res)=>res.sendFile(path.join(__dirname,"..","public","admin-ui","login.html")));
r.get("/ui/audit", (req,res)=>res.sendFile(path.join(__dirname,"..","public","admin-ui","audit.html")));

module.exports=r;
