1. Buy server in your friendly country(relay) and foreign country(exit)
2. Buy domain for your friendly country
3. In .env set your domain
4. Execute bash `setup-caddy.sh` on relay server
5. Execute `install_xray.sh` on relay and exit server
6. Execute `generate_config.sh` with exit and relay servers
7. Generate new clients with `add_user_relay` script