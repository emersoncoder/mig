### Visão geral da arquitetura

* **Orquestração local com Docker Compose**: A raiz do projeto contém um `compose.yaml` que sobe Traefik como proxy reverso, um serviço de teste `whoami` e a API PHP, todos conectados à mesma rede `proxy`, com Traefik expondo portas 8089 (HTTP) e 8099 (dashboard). Labels configuram roteamento com strip prefix para a API e uma rota raiz provisória que ainda aponta para o `whoami`.

* **Scripts de automação**: O script `boot.mig.local.sh` automatiza a geração do arquivo Compose, provisiona o esqueleto Laravel, garante arquivos de saúde em `public`, ajusta permissões e executa testes de roteamento para validar Traefik, a API e o health-check estático.

* **Fluxo de uso**: O `README.md` destaca o objetivo de servir API e Web sob um único host `mig.localhost`, lista requisitos (Docker/Compose e entrada no `/etc/hosts`) e fornece comandos `make` básicos para subir, inspecionar e derrubar a stack.


### Backend (API)

* **Framework**: Laravel 12 rodando em PHP ≥ 8.2, conforme `composer.json`, com dependências padrão de desenvolvimento como PHPUnit, Laravel Sail e Pint.

* **Runtime**: A imagem base do contêiner é `dunglas/frankenphp:1-php8.3`, com instalação de extensões necessárias (PDO MySQL, ICU, ZIP). Isso indica uso do servidor FrankenPHP, que combina PHP-FPM e HTTP/2/3 nativo.

* **Estado atual**: As rotas web incluem apenas a página `welcome` padrão e múltiplas duplicatas de um endpoint `/health` que retorna JSON, evidenciando estágio inicial de configuração.


### Frontend (Web)

* **Frameworks/bibliotecas**: Aplicação Next.js 15 (modo app router) com React 19 e TypeScript, Tailwind CSS 4 e ESLint 9, segundo `package.json`.

* **Funcionalidade presente**: A página principal (`src/app/page.tsx`) é um componente client-side que busca `/api/health` sem cache, exibindo o status retornado pela API e um cabeçalho “ERP Moderno — mig”.


### Considerações adicionais

* O repositório posiciona Traefik como peça central para rotear tanto a API (PHP/Laravel/FrankenPHP) quanto o front-end Next.js, com um serviço `whoami` provisório segurando a raiz até que a aplicação web esteja pronta.

* Scripts auxiliares (`Makefile`, `boot.mig.local.sh`, `versao.api_web.sh`, `reset.mig.sh`) visam facilitar o ciclo de desenvolvimento local e manutenção das versões API/Web, seguindo a proposta de uma base “Fundação” para evoluir o ERP moderno.

