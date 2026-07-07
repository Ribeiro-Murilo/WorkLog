APP_NAME      := WorkLog
PROJECT       := WorkLog.xcodeproj
SCHEME        := WorkLog
BUILD_DIR     := build
ARCHIVE_PATH  := $(BUILD_DIR)/$(APP_NAME).xcarchive
APP_PATH      := $(ARCHIVE_PATH)/Products/Applications/$(APP_NAME).app
ZIP_PATH      := $(BUILD_DIR)/$(APP_NAME).zip

.PHONY: help build release dist publish test run icon clean

help:
	@echo "Alvos disponíveis:"
	@echo "  make build            - compila o app em Debug"
	@echo "  make run              - compila em Debug e abre o app"
	@echo "  make test             - roda os testes unitários"
	@echo "  make release          - gera o archive de Release (.xcarchive)"
	@echo "  make dist             - gera o archive e empacota WorkLog.zip pronto para distribuir"
	@echo "  make publish VERSION=x.y.z - builda, assina e prepara o appcast.xml para o Sparkle (ver scripts/release.sh)"
	@echo "  make icon IMAGE=path  - gera o ícone do app a partir de uma imagem (PNG, de preferência quadrada)"
	@echo "  make clean            - remove a pasta build/"

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination 'platform=macOS' build

run: build
	@APP_DIR=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -showBuildSettings 2>/dev/null | awk -F'= ' '/ BUILT_PRODUCTS_DIR/{print $$2; exit}'); \
	open "$$APP_DIR/$(APP_NAME).app"

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' test -only-testing:$(APP_NAME)Tests

release:
	rm -rf $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination 'platform=macOS' archive -archivePath $(ARCHIVE_PATH)

dist: release
	ditto -c -k --keepParent "$(APP_PATH)" "$(ZIP_PATH)"
	@echo ""
	@echo "Pronto! App empacotado em: $(ZIP_PATH)"
	@echo "Como o app não é assinado com uma conta Apple Developer paga,"
	@echo "quem for abrir em outro Mac deve clicar com o botão direito no"
	@echo "WorkLog.app e escolher \"Abrir\" na primeira execução."

publish:
	@if [ -z "$(VERSION)" ]; then \
		echo "Uso: make publish VERSION=x.y.z"; \
		exit 1; \
	fi
	./scripts/release.sh $(VERSION)

icon:
	@if [ -z "$(IMAGE)" ]; then \
		echo "Uso: make icon IMAGE=/caminho/para/imagem.png"; \
		exit 1; \
	fi
	./scripts/generate_app_icon.sh "$(IMAGE)"

clean:
	rm -rf $(BUILD_DIR)
