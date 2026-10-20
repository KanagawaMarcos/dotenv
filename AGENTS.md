# Política deste repositório

`~/Git/dotenv` é a fonte canônica da configuração declarativa deste PC NixOS.

- Faça mudanças de sistema, pacotes, serviços, atalhos e integrações neste
  repositório; não edite a cópia legada em `/etc/nixos`.
- Valide e aplique pelo flake com `nixos build`.
- Para toda alteração concluída neste repositório: faça `git add`, crie um
  commit descritivo e envie para `origin/main` com `git push origin main`.
- Nunca versione chaves privadas, tokens, cookies, credenciais de aplicativos
  ou material secreto sem criptografia. Documente dependências externas em vez
  de copiá-las para o Git.
