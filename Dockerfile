# The website, served by Caddy from the tree that is already published.
#
# docs/ is what GitHub Pages serves, and `npm run verify` checks it against
# web/ on every push — so it is already the repository's single statement of
# what is live. Building the site again here would create a second answer to
# that question and a second way for the two to drift apart. This image copies
# the answer CI already checks.
#
# It also keeps the runtime image to a file server and 3.4MB of site: no Node,
# no node_modules, no build tooling, nothing with a CVE feed.
FROM caddy:2.8-alpine

COPY Caddyfile /etc/caddy/Caddyfile
COPY docs /srv

# Railway supplies the real port through $PORT and the Caddyfile reads it.
# This is the local default, for `docker run -p 8080:8080`.
EXPOSE 8080
