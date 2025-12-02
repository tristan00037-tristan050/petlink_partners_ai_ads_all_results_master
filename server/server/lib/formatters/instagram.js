module.exports = {
  format({ headline='', body='', hashtags=[], links=[] }, rules){
    const hMax = rules?.max_len_headline ?? 60;
    const bMax = rules?.max_len_body ?? 2200;
    const tagMax = rules?.max_hashtags ?? 30;
    const allowLinks = (rules?.allow_links ?? true);

    const H = headline.trim().slice(0, hMax);
    const tags = (hashtags||[]).slice(0, tagMax).map(t=> t.startsWith('#')? t : ('#'+t));
    let B = body.trim().slice(0, bMax);
    if(!allowLinks) B = B.replace(/https?:\/\/\S+/g, '');
    return { headline:H, body:B, hashtags:tags, links: allowLinks? links||[]: [] };
  }
}
