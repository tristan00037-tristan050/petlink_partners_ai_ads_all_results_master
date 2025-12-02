module.exports={ 
  async validateToken(){return{ok:true,mock:true}}, 
  async authorize(){return{ok:true,status:'AUTHORIZED',mock:true}},
  async capture(){return{ok:true,status:'CAPTURED',mock:true,provider_txn_id:'mock-'+Date.now()}}, 
  async verify(){return{ok:true,status:'CAPTURED',mock:true}},
  async webhookVerify({raw,ts,sig,secret}){return{ok:true,mock:true}} 
};
