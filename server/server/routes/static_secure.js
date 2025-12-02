const express = require("express");
const path = require("path");
const securityHeaders = require("../mw/security_headers");
const { appCORS, adminCORS } = require("../mw/cors_split") || { appCORS: (req,res,next)=>next(), adminCORS: (req,res,next)=>next() };
const r = express.Router();

// app-ui/login.html
r.get("/app/login", appCORS, securityHeaders, (req, res) => {
  res.sendFile(path.join(__dirname, "..", "public", "app-ui", "login.html"));
});

// admin-ui/login.html  
r.get("/admin/spa/login", adminCORS, securityHeaders, (req, res) => {
  res.sendFile(path.join(__dirname, "..", "public", "admin-ui", "login.html"));
});

module.exports = r;
