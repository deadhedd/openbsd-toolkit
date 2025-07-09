# Load file-based SSH keys into env vars
for user in GIT OBS; do
  pk_file_var="${user}_SSH_PRIVATE_KEY_FILE"
  pub_file_var="${user}_SSH_PUBLIC_KEY_FILE"
  if [ -n "${!pk_file_var}" ] && [ -f "${!pk_file_var}" ]; then
    export "${user}_SSH_PRIVATE_KEY"="$(< "${!pk_file_var}")"
  fi
  if [ -n "${!pub_file_var}" ] && [ -f "${!pub_file_var}" ]; then
    export "${user}_SSH_PUBLIC_KEY"="$(< "${!pub_file_var}")"
  fi
done

