// mirrors remote_id() in bin/mmm: git@h:o/r.git, https://h/o/r and ssh://git@h/o/r all become "h/o/r"
export function remoteId(url) {
  let rest = String(url).trim().replace(/^[a-z+]+:\/\//i, '');
  rest = rest.replace(/^[^@/]*@/, '').replace(/^([^/:]+):/, '$1/');
  return rest.replace(/\.git$/, '').replace(/\/$/, '');
}
