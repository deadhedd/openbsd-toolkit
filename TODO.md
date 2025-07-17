- [x] Dump test results to a log file 
- [x] create the obsidian user
- [x] script configs for new failing tests
- [x] fix organizational comments in test_obsidian_user
- [x] add tests for the setup actions that dont currently have tests in test_obsidian_user
- [x] Create a secrets file for configuring environment variable defaults
- [x] implement secrets retreival in setup and test scripts
- [x] add admin user setup to setup_system.sh
- [x] update REG_USER usages to OBS_USER
- [x] wrap work_tree setting in quotes 
- [x] update the name STATIC_IP to GIT_SERVER
- [x] specify master branch in post-receive
- [x] add "doas -u OBS_USER" to post-receive
- [x] add "premit nopass git as obsidian cmd git" to doas.conf
- [ ] set -x post receive
- [ ] create shared group and add both git and obsidian
- [ ] chown -R git:vault /home/git/vaults/Main.git; chmod -R g+rwX /home/git/vaults/Main.git; find /home/git/vaults/Main.git -type d -exec chmod g+s {} +
- [ ] add to /home/git/vaults/Main.git/config: [core]
                                                    sharedRepository = group
- [ ] cd /home/git/vaults/Main.git
SHA=$(cat refs/heads/master)

su - obsidian -s /bin/sh -c \
  "/usr/local/bin/git \
    --git-dir=$(pwd) \
    --work-tree=/home/obsidian/vaults/Main \
    checkout -f $SHA"
- [ ] 1.0?
- [ ] add logging to post receive hook for troubleshooting
- [ ] add ssh keys handling for git host
- [ ] make setup idempotent
- [ ] improve error handling
- [ ] create client side obsidian git setup script 
- [ ] add support for hints in test suite
- [ ] Github user config
- [ ] Add functional testing 
- [ ] Create teardown script for easier testing 
- [ ] Better ux for choosing scripts to run 
- [ ] Incorporate timeouts for network tests
- [ ] Attempt blocked doas command to confirm denial 
- [ ] obsidian daily note scripts
- [ ] Build a custom ISO
- [ ] recovery partition 
