# Limitando Recursos

kubectl edit deployments deploy-wwww

kubectl exec -it <container> -- bash

apt update && apt install -y stress

stress --vm 1 --vm-bytes 128M --cpu 1  # E vai aumentando os números conforme os limites