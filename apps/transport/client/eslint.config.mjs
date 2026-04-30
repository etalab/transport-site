import js from '@eslint/js'
import globals from 'globals'
import prettier from 'eslint-config-prettier/flat'

export default [
    js.configs.recommended,
    {
        languageOptions: {
            ecmaVersion: 'latest',
            sourceType: 'module',
            globals: {
                ...globals.browser,
                ...globals.node,
                opts: 'readonly'
            }
        },
        rules: {
            'no-unused-vars': [
                'error',
                {
                    args: 'after-used',
                    argsIgnorePattern: '^_',
                    caughtErrorsIgnorePattern: '^_',
                    varsIgnorePattern: '^_'
                }
            ]
        }
    },
    prettier,
    {
        ignores: ['node_modules/', 'priv/', 'build/', 'dist/']
    }
]
