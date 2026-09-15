// Auto-generated from production schema
// CODE-01: Supabase Database types
// Do not edit manually — regenerate with: node scripts/gen-types.mjs

export interface Database {
  public: {
    Tables: {
      account_tag_mappings: {
        Row: {
          id: string
          tenant_id: string | null
          tag_id: string
          entity_type: string
          entity_id: string
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      account_tags: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          applicability: string
          color: string | null
          country_code: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      accounting_control_runs: {
        Row: {
          id: string
          tenant_id: string | null
          control_type: string
          fiscal_year_id: string | null
          period_id: string | null
          run_date: string
          status: string
          total_checks: number
          errors_found: number
          warnings_found: number
          details: Record<string, any>
          created_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      analytic_distribution_lines: {
        Row: {
          id: string
          tenant_id: string | null
          journal_line_id: string | null
          plan_id: string | null
          section_id: string | null
          percentage: number
          amount: number | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      analytic_journal_codes: {
        Row: {
          id: string
          tenant_id: string | null
          code: string
          name: string
          description: string | null
          type: string | null
          is_active: boolean | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      analytic_plans: {
        Row: {
          id: string
          tenant_id: string | null
          code: string
          name: string
          description: string | null
          is_default: boolean
          active: boolean
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      analytic_sections: {
        Row: {
          id: string
          code: string
          name: string
          parent_id: string | null
          axis: string | null
          level: number | null
          active: boolean | null
          created_at: string | null
          tenant_id: string
          plan_id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      approval_workflows: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          entity_type: string
          steps: Record<string, any> | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      asset_batch_disposal_lines: {
        Row: {
          id: string
          tenant_id: string | null
          batch_id: string
          asset_id: string
          disposal_type: string | null
          proceeds: number | null
          net_book_value: number | null
          gain_loss: number | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      asset_batch_disposals: {
        Row: {
          id: string
          tenant_id: string | null
          batch_number: string
          disposal_date: string
          total_assets: number | null
          total_proceeds: number | null
          total_gain_loss: number | null
          status: string | null
          journal_entry_id: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      asset_depreciation_plans: {
        Row: {
          id: string
          tenant_id: string | null
          asset_id: string
          plan_type: string
          depreciation_method: string | null
          duration_months: number
          residual_value: number | null
          annual_rate: number | null
          start_date: string
          end_date: string | null
          accumulated_depreciation: number | null
          current_net_value: number | null
          active: boolean | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      asset_depreciations: {
        Row: {
          id: string
          asset_id: string
          fiscal_year_code: string | null
          period: number
          depreciation_type: string
          amount: number
          cumulative_amount: number
          net_book_value: number
          entry_number: string | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      asset_documents: {
        Row: {
          id: string
          tenant_id: string | null
          asset_id: string
          document_type: string | null
          file_url: string
          file_name: string | null
          description: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      asset_families: {
        Row: {
          id: string
          tenant_id: string | null
          code: string
          name: string
          parent_id: string | null
          default_account: string | null
          default_depreciation_account: string | null
          default_duration_months: number | null
          default_method: string | null
          depreciation_rate: number | null
          description: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      asset_free_fields: {
        Row: {
          id: string
          tenant_id: string | null
          asset_id: string
          field_key: string
          field_value: string | null
          field_type: string | null
          field_category: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      asset_revaluations: {
        Row: {
          id: string
          tenant_id: string | null
          asset_id: string
          revaluation_date: string
          old_value: number
          new_value: number
          difference: number | null
          reason: string | null
          journal_entry_id: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      asset_split_components: {
        Row: {
          id: string
          tenant_id: string | null
          split_id: string
          new_asset_id: string
          allocated_value: number
          allocated_percentage: number | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      asset_splits: {
        Row: {
          id: string
          tenant_id: string | null
          original_asset_id: string
          split_date: string
          reason: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      at_rates: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          rate: number
          bonus_malus_rate: number | null
          effective_date: string
          expiry_date: string | null
          risk_category: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      audit_log: {
        Row: {
          id: string
          user_id: string | null
          action: string
          entity_type: string
          entity_id: string | null
          entity_number: string | null
          description: string | null
          metadata: Record<string, any> | null
          ip_address: string | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      auto_label_rules: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          description: string | null
          journal_code: string | null
          account_code: string | null
          account_prefix: string | null
          label_pattern: string
          priority: number
          active: boolean
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      bank_accounts: {
        Row: {
          id: string
          name: string
          type: string
          account_number: string | null
          sort_code: string | null
          balance: number | null
          currency: string | null
          bank_name: string | null
          last_reconciled: string | null
          connected: boolean | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          statement_balance: number | null
          statement_balance_date: string | null
          calculated_balance: number | null
          reconciliation_diff: number | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      bank_connections: {
        Row: {
          id: string
          tenant_id: string | null
          provider: string
          provider_connection_id: string | null
          bank_account_id: string | null
          status: string | null
          last_sync_at: string | null
          sync_frequency: string | null
          next_sync_at: string | null
          error_message: string | null
          metadata: Record<string, any> | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      bank_reconciliation_rules: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          afb_code: string
          description: string | null
          match_pattern: string | null
          counterpart_account: string | null
          journal_code: string | null
          priority: number
          active: boolean
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      bank_rules: {
        Row: {
          id: string
          name: string
          condition_field: string
          condition_operator: string
          condition_value: string
          action_category: string
          action_account_code: string | null
          action_vat_rate: number | null
          priority: number | null
          active: boolean | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      bank_statement_imports: {
        Row: {
          id: string
          tenant_id: string | null
          bank_account_id: string | null
          filename: string
          format: string
          file_size: string | null
          status: string
          imported_count: number | null
          error_message: string | null
          imported_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      bank_statement_templates: {
        Row: {
          id: string
          tenant_id: string | null
          bank_name: string
          account_number_pattern: string | null
          date_pattern: string
          amount_pattern: string
          description_pattern: string | null
          reference_pattern: string | null
          debit_indicator: string | null
          credit_indicator: string | null
          period_pattern: string | null
          balance_pattern: string | null
          currency_pattern: string | null
          skip_lines_pattern: string | null
          sample_text: string | null
          is_active: boolean | null
          created_at: string | null
          updated_at: string | null
          bank_id: string | null
          validation_status: string
          consecutive_successes: number
          validation_count: number
          last_validated_at: string | null
          last_correction_notes: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      bank_transactions: {
        Row: {
          id: string
          account_id: string | null
          date: string
          description: string
          reference: string | null
          type: string
          amount: number
          category: string | null
          reconciled: boolean | null
          matched: boolean | null
          invoice_id: string | null
          purchase_invoice_id: string | null
          created_at: string | null
          tenant_id: string
          afb_code: string | null
          reconciled_entry_id: string | null
          reconciled_at: string | null
          original_currency: string | null
          original_amount: number | null
          exchange_rate: number | null
          exchange_gain_loss: number | null
          source: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      banks: {
        Row: {
          id: string
          name: string
          swift_code: string | null
          country: string | null
          logo_url: string | null
          is_active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      batch_entry_sessions: {
        Row: {
          id: string
          tenant_id: string | null
          session_name: string
          journal_code: string
          session_date: string
          entry_count: number
          total_debit: number
          total_credit: number
          status: string
          validated_at: string | null
          validated_by: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      bdes_indicators: {
        Row: {
          id: string
          tenant_id: string | null
          year: number
          category: string
          indicator_name: string
          indicator_value: number | null
          indicator_unit: string | null
          breakdown: Record<string, any> | null
          target_value: number | null
          previous_year_value: number | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      bom_lines: {
        Row: {
          id: string
          bom_id: string | null
          product_id: string
          quantity: number
          unit_cost: number | null
          position: number | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      boms: {
        Row: {
          id: string
          code: string
          name: string
          product_id: string | null
          quantity: number | null
          unit: string | null
          active: boolean | null
          created_at: string | null
          tenant_id: string
          routing_id: string | null
          bom_type: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      budget_commitments: {
        Row: {
          id: string
          description: string
          account_code: string
          fiscal_year_id: string | null
          amount: number
          commitment_date: string
          source_type: string | null
          source_id: string | null
          status: string
          supplier_id: string | null
          notes: string | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      budgets: {
        Row: {
          id: string
          name: string
          fiscal_year_id: string | null
          account_code: string | null
          analytic_section_id: string | null
          period_1: number | null
          period_2: number | null
          period_3: number | null
          period_4: number | null
          period_5: number | null
          period_6: number | null
          period_7: number | null
          period_8: number | null
          period_9: number | null
          period_10: number | null
          period_11: number | null
          period_12: number | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      career_history: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          position: string | null
          department: string | null
          salary: number | null
          start_date: string
          end_date: string | null
          change_type: string | null
          notes: string | null
          created_at: string | null
          event_type: string | null
          event_date: string | null
          previous_position: string | null
          new_position: string | null
          previous_department: string | null
          new_department: string | null
          previous_salary: number | null
          new_salary: number | null
          previous_manager_id: string | null
          new_manager_id: string | null
          previous_collective_agreement_id: string | null
          new_collective_agreement_id: string | null
          reason: string | null
          documents: Record<string, any> | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      carry_forward_log: {
        Row: {
          id: string
          tenant_id: string | null
          source_fiscal_year_id: string
          target_fiscal_year_id: string
          carry_forward_date: string
          total_debit: number
          total_credit: number
          entry_count: number
          status: string
          journal_entry_id: string | null
          created_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      cash_control_sessions: {
        Row: {
          id: string
          tenant_id: string | null
          session_number: string
          journal_code: string
          session_date: string
          theoretical_balance: number
          counted_balance: number
          difference: number
          status: string
          counted_by: string | null
          validated_by: string | null
          validated_at: string | null
          notes: string | null
          details: Record<string, any>
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      chart_account_templates: {
        Row: {
          id: string
          pack_code: string
          code: string
          name: string
          type: string
          vat_rate: string | null
          parent_code: string | null
          sort_order: number | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      chart_accounts: {
        Row: {
          id: string
          code: string
          name: string
          type: string
          balance: number | null
          vat_rate: string | null
          description: string | null
          parent_id: string | null
          created_at: string | null
          tenant_id: string
          racine: string | null
          classe: string | null
          nature: string | null
          code_taxe_default: string | null
          saisie_analytic: boolean | null
          saisie_echeance: boolean | null
          saisie_tiers: boolean | null
          debit_n1: number | null
          credit_n1: number | null
          current_debit: number | null
          current_credit: number | null
          current_balance: number | null
          currency_code: string | null
          reconcile: boolean | null
          deprecated: boolean | null
          account_type: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      check_books: {
        Row: {
          id: string
          tenant_id: string | null
          bank_account_id: string | null
          journal_id: string | null
          name: string
          first_check_number: string
          last_check_number: string
          next_check_number: string
          status: string | null
          issued_count: number | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      checks: {
        Row: {
          id: string
          tenant_id: string | null
          check_book_id: string | null
          check_number: string
          amount: number
          payee: string
          issue_date: string
          due_date: string | null
          status: string | null
          journal_entry_id: string | null
          payment_id: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      cice_config: {
        Row: {
          id: string
          tenant_id: string | null
          year: number
          smic_threshold: number | null
          rate: number | null
          eligible_salary_cap: number | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      collection_reminders: {
        Row: {
          id: string
          number: string
          customer_id: string | null
          third_party_id: string | null
          invoice_id: string | null
          reminder_level: number
          reminder_date: string
          due_date: string | null
          amount: number
          status: string
          notes: string | null
          created_at: string | null
          tenant_id: string
          payment_link_token: string | null
          payment_link_url: string | null
          payment_link_expires_at: string | null
          payment_status: string | null
          reminder_level_id: string | null
          dispute_id: string | null
          promise_id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      compaction_logs: {
        Row: {
          id: string
          tenant_id: string | null
          fiscal_year_id: string | null
          entries_compacted: number
          lines_compacted: number
          status: string
          compacted_by: string | null
          compacted_at: string
          details: Record<string, any> | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      company_settings: {
        Row: {
          id: string
          name: string
          legal_name: string | null
          vat_number: string | null
          siret: string | null
          address: string | null
          city: string | null
          postal_code: string | null
          country: string | null
          currency: string | null
          fiscal_year_start: string | null
          email: string | null
          phone: string | null
          website: string | null
          logo_url: string | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          country_code: string | null
          legislation_pack_code: string | null
          vat_method: string | null
          gdpr_enabled: boolean | null
          gdpr_retention_years: number | null
          gdpr_anonymize_after: boolean | null
          accounting_standard: string | null
          saisie_negative: boolean | null
          multi_currency: boolean | null
          show_quantities: boolean | null
          vat_regime: string | null
          vat_periodicity: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      consolidated_treasury: {
        Row: {
          id: string
          tenant_id: string | null
          consolidation_date: string
          total_assets: number | null
          total_liabilities: number | null
          net_position: number | null
          details: Record<string, any> | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      contracts: {
        Row: {
          id: string
          number: string
          employee_id: string
          contract_type: string
          start_date: string
          end_date: string | null
          position: string | null
          department: string | null
          monthly_salary: number | null
          hourly_rate: number | null
          weekly_hours: number | null
          trial_period_days: number | null
          status: string
          notes: string | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      corporate_tax_grid_lines: {
        Row: {
          id: string
          grid_id: string
          line_type: string
          label: string
          base_type: string
          min_amount: number | null
          max_amount: number | null
          rate: number | null
          cap_amount: number | null
          fixed_amount: number | null
          sort_order: number
          created_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      corporate_tax_grids: {
        Row: {
          id: string
          tenant_id: string | null
          country_code: string
          tax_type: string
          name: string
          description: string | null
          effective_from: string
          effective_to: string | null
          status: string
          source: string
          file_url: string | null
          is_default: boolean
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      cpf_accounts: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          balance_hours: number | null
          balance_amount: number | null
          history: Record<string, any> | null
          created_at: string | null
          updated_at: string | null
          last_sync_date: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      cpf_transactions: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          transaction_type: string
          hours: number | null
          amount: number | null
          training_label: string | null
          training_start_date: string | null
          training_end_date: string | null
          training_provider: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      credit_lines: {
        Row: {
          id: string
          tenant_id: string | null
          bank_account_id: string | null
          name: string
          type: string | null
          limit_amount: number
          used_amount: number | null
          interest_rate: number | null
          start_date: string | null
          end_date: string | null
          monthly_payment: number | null
          status: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      credit_note_lines: {
        Row: {
          id: string
          credit_note_id: string | null
          description: string
          quantity: number | null
          unit_price: number | null
          vat_rate: number | null
          total: number | null
          vat_total: number | null
          line_order: number | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      credit_notes: {
        Row: {
          id: string
          number: string
          customer_id: string | null
          customer_name: string | null
          date: string
          status: string
          subtotal: number | null
          vat_total: number | null
          total: number | null
          reason: string | null
          invoice_id: string | null
          created_at: string | null
          tenant_id: string
          currency_code: string | null
          exchange_rate: number | null
          amount_untaxed_currency: number | null
          amount_tax_currency: number | null
          amount_total_currency: number | null
          source_invoice_id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      crm_activities: {
        Row: {
          id: string
          tenant_id: string | null
          opportunity_id: string | null
          customer_id: string | null
          activity_type: string
          subject: string
          description: string | null
          scheduled_date: string | null
          completed_date: string | null
          duration_minutes: number | null
          status: string | null
          assigned_to: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      crm_campaign_recipients: {
        Row: {
          id: string
          tenant_id: string | null
          campaign_id: string
          customer_id: string | null
          prospect_id: string | null
          email: string | null
          phone: string | null
          sent: boolean | null
          sent_at: string | null
          opened: boolean | null
          opened_at: string | null
          clicked: boolean | null
          responded: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      crm_campaigns: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          description: string | null
          campaign_type: string
          status: string | null
          start_date: string | null
          end_date: string | null
          budget: number | null
          actual_cost: number | null
          target_audience: string | null
          segment_criteria: Record<string, any> | null
          sent_count: number | null
          open_count: number | null
          click_count: number | null
          response_count: number | null
          conversion_count: number | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      crm_forecasts: {
        Row: {
          id: string
          tenant_id: string | null
          period: string
          sales_rep_id: string | null
          target_amount: number | null
          committed_amount: number | null
          best_case_amount: number | null
          pipeline_amount: number | null
          closed_amount: number | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      crm_opportunities: {
        Row: {
          id: string
          tenant_id: string | null
          number: string
          customer_id: string | null
          prospect_id: string | null
          title: string
          description: string | null
          stage: string
          probability: number | null
          expected_amount: number | null
          expected_close_date: string | null
          actual_amount: number | null
          actual_close_date: string | null
          sales_rep_id: string | null
          source: string | null
          lost_reason: string | null
          tags: string | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      crm_territories: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          code: string | null
          parent_id: string | null
          sales_rep_id: string | null
          regions: string | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      currencies: {
        Row: {
          id: string
          code: string
          name: string
          symbol: string | null
          exchange_rate: number | null
          is_base: boolean | null
          created_at: string | null
          tenant_id: string
          last_rate_date: string | null
          decimal_places: number | null
          rounding: number | null
          active: boolean | null
          position: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      currency_revaluations: {
        Row: {
          id: string
          tenant_id: string | null
          fiscal_year_id: string | null
          period_date: string
          account_code: string
          third_party_code: string | null
          currency: string
          original_rate: number
          new_rate: number
          original_amount: number
          original_amount_eur: number
          revalued_amount_eur: number
          gain_loss: number
          type: string
          status: string
          entry_id: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      custom_report_templates: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          description: string | null
          report_type: string
          category: string
          columns: Record<string, any>
          filters: Record<string, any>
          group_by: string | null
          sort_by: string | null
          sort_order: string | null
          page_orientation: string | null
          page_size: string | null
          header_text: string | null
          footer_text: string | null
          show_logo: boolean
          show_date: boolean
          show_page_numbers: boolean
          active: boolean
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      customer_contacts: {
        Row: {
          id: string
          tenant_id: string | null
          customer_id: string
          name: string
          role: string | null
          email: string | null
          phone: string | null
          mobile: string | null
          is_default: boolean | null
          active: boolean | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      customer_payments: {
        Row: {
          id: string
          number: string
          customer_id: string | null
          invoice_id: string | null
          payment_date: string
          amount: number
          method: string | null
          bank_account_id: string | null
          reference: string | null
          status: string
          created_at: string | null
          tenant_id: string
          currency_code: string | null
          exchange_rate: number | null
          amount_currency: number | null
          exchange_gain_loss: number | null
          transferred_entry_id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      customers: {
        Row: {
          id: string
          name: string
          email: string | null
          phone: string | null
          address: string | null
          city: string | null
          postal_code: string | null
          country: string | null
          vat_number: string | null
          contact_name: string | null
          balance: number | null
          credit_limit: number | null
          payment_terms: string | null
          currency: string | null
          active: boolean | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          legal_form: string | null
          ape_code: string | null
          naf_code: string | null
          employee_count_range: string | null
          revenue_range: string | null
          payment_delay_avg: number | null
          siret: string | null
          sector_code: string | null
          geographic_zone: string | null
          parent_id: string | null
          is_company: boolean | null
          sales_rep_id: string | null
          currency_code: string | null
          bank_account_id: string | null
          price_list_id: string | null
          email_settings: Record<string, any> | null
          credit_used: number | null
          credit_blocked: boolean | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      dashboard_widgets: {
        Row: {
          id: string
          tenant_id: string | null
          user_id: string
          widget_type: string
          title: string
          config: Record<string, any> | null
          position: number
          size: string
          visible: boolean | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      deferred_printing_jobs: {
        Row: {
          id: string
          tenant_id: string | null
          job_name: string
          report_type: string
          parameters: Record<string, any>
          scheduled_date: string
          status: string
          output_format: string
          output_data: string | null
          generated_at: string | null
          generated_by: string | null
          error_message: string | null
          created_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      delivery_note_lines: {
        Row: {
          id: string
          delivery_note_id: string | null
          product_id: string | null
          description: string
          quantity: number
          tenant_id: string
          ordered_quantity: number | null
          invoiced_quantity: number | null
          sales_order_line_id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      delivery_notes: {
        Row: {
          id: string
          number: string
          customer_id: string | null
          sales_order_id: string | null
          delivery_date: string
          status: string
          carrier: string | null
          tracking_number: string | null
          notes: string | null
          created_at: string | null
          tenant_id: string
          validation_status: string | null
          fully_invoiced: boolean | null
          invoice_status: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      delivery_schedules: {
        Row: {
          id: string
          tenant_id: string | null
          customer_id: string | null
          product_id: string
          frequency: string | null
          quantity: number
          start_date: string
          end_date: string | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      disputes: {
        Row: {
          id: string
          tenant_id: string | null
          third_party_code: string
          invoice_ref: string | null
          amount: number
          reason: string
          status: string
          resolution: string | null
          opened_date: string
          resolved_date: string | null
          created_by: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      distribution_grill_lines: {
        Row: {
          id: string
          grill_id: string | null
          section_code: string
          percentage: number
          created_at: string
          tenant_id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      distribution_grills: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          description: string | null
          account_code: string
          journal_code: string | null
          active: boolean
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      document_charges: {
        Row: {
          id: string
          tenant_id: string | null
          document_type: string
          document_id: string
          charge_type: string
          label: string
          amount: number | null
          vat_rate: number | null
          vat_amount: number | null
          total_amount: number | null
          supplier_id: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      document_distribution_logs: {
        Row: {
          id: string
          tenant_id: string | null
          batch_id: string | null
          employee_document_id: string | null
          employee_id: string
          document_type: string | null
          period: string | null
          distributed_at: string | null
          acknowledged_at: string | null
          status: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      document_shares: {
        Row: {
          id: string
          tenant_id: string | null
          document_type: string
          document_id: string
          shared_with_email: string
          share_token: string
          share_url: string | null
          expires_at: string | null
          viewed: boolean | null
          viewed_at: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      document_templates: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          document_type: string
          logo_url: string | null
          primary_color: string | null
          secondary_color: string | null
          template_config: Record<string, any> | null
          is_default: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      document_transformations: {
        Row: {
          id: string
          tenant_id: string | null
          source_type: string
          source_id: string
          target_type: string
          target_id: string
          transformation_type: string
          transformed_by: string | null
          transformed_at: string | null
          notes: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      dpae_records: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          hire_date: string
          contract_type: string | null
          position: string | null
          status: string | null
          transmitted_at: string | null
          response_code: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      dsn_declarations: {
        Row: {
          id: string
          tenant_id: string | null
          period: string
          type: string | null
          status: string | null
          file_url: string | null
          generated_at: string | null
          transmitted_at: string | null
          response_code: string | null
          response_message: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      electronic_signatures: {
        Row: {
          id: string
          tenant_id: string | null
          document_type: string
          document_id: string
          signer_name: string
          signer_email: string | null
          signature_hash: string | null
          signature_data: string | null
          ip_address: string | null
          signed_at: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      employee_activity_logs: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          activity_type: string
          description: string | null
          metadata: Record<string, any> | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      employee_documents: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          document_type: string
          file_url: string
          file_name: string | null
          distributed_at: string | null
          acknowledged_at: string | null
          created_at: string | null
          title: string
          file_size: string | null
          mime_type: string | null
          period: string | null
          uploaded_by: string | null
          visible_to_employee: boolean | null
          requires_acknowledgment: boolean | null
          acknowledged: boolean | null
          e_signed: boolean | null
          e_signed_at: string | null
          e_signature_hash: string | null
          archived: boolean | null
          archive_date: string | null
          retention_years: number | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      employee_exit_processes: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          exit_date: string
          exit_reason: string
          step: number | null
          status: string | null
          cp_indemnity: number | null
          rtt_indemnity: number | null
          recovery_indemnity: number | null
          bonus_amount: number | null
          advance_deduction: number | null
          overtime_amount: number | null
          total_gross: number | null
          total_net: number | null
          work_certificate_url: string | null
          settlement_receipt_url: string | null
          pole_emploi_attestation_url: string | null
          dsn_exit_url: string | null
          documents_generated: boolean | null
          dsn_exit_generated: boolean | null
          dsn_exit_transmitted: boolean | null
          exit_payslip_id: string | null
          notes: string | null
          created_at: string | null
          completed_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      employee_objectives: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          campaign_id: string | null
          title: string
          description: string | null
          target_value: number | null
          current_value: number | null
          unit: string | null
          period: string | null
          frequency: string | null
          status: string | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      employees: {
        Row: {
          id: string
          name: string
          email: string | null
          phone: string | null
          position: string | null
          department: string | null
          salary: number | null
          hire_date: string | null
          status: string
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          employee_number: string | null
          social_security_number: string | null
          birth_date: string | null
          address: string | null
          city: string | null
          postal_code: string | null
          contract_type: string | null
          contract_end_date: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          emergency_contact_relation: string | null
          photo_url: string | null
          bank_iban: string | null
          bank_bic: string | null
          bank_account_holder: string | null
          transport_mode: string | null
          transport_cost: number | null
          meal_voucher_count: number | null
          meal_voucher_value: number | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      entry_templates: {
        Row: {
          id: string
          name: string
          journal_code: string | null
          description: string | null
          template_lines: Record<string, any> | null
          is_default: boolean | null
          active: boolean | null
          created_at: string | null
          tenant_id: string
          counterpart_account: string | null
          payment_terms: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      etat_rapprochement: {
        Row: {
          id: string
          tenant_id: string | null
          bank_account_id: string | null
          account_code: string
          period_start: string
          period_end: string
          bank_balance: number
          book_balance: number
          difference: number
          reconciled_items: number | null
          unreconciled_items: number | null
          generated_at: string
          generated_by: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      exchange_gain_loss_entries: {
        Row: {
          id: string
          tenant_id: string | null
          payment_id: string | null
          invoice_id: string | null
          type: string
          amount: number | null
          exchange_rate_original: number | null
          exchange_rate_payment: number | null
          account_gain_code: string | null
          account_loss_code: string | null
          journal_entry_id: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      exchange_rates: {
        Row: {
          id: string
          tenant_id: string | null
          base_currency: string
          quote_currency: string
          rate: number
          rate_date: string
          source: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      expense_categories: {
        Row: {
          id: string
          tenant_id: string | null
          code: string
          label: string
          account_code: string | null
          vat_rate: number | null
          max_amount: number | null
          max_monthly: number | null
          requires_receipt: boolean | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      expense_report_lines: {
        Row: {
          id: string
          tenant_id: string | null
          expense_report_id: string
          date: string
          description: string
          category: string | null
          amount: number
          vat_rate: number | null
          vat_amount: number | null
          receipt_url: string | null
          created_at: string | null
          category_id: string | null
          amount_ht: number | null
          amount_ttc: number | null
          ocr_data: Record<string, any> | null
          ocr_processed: boolean | null
          ceiling_exceeded: boolean | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      expense_reports: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          number: string
          period: string | null
          total_amount: number | null
          total_vat: number | null
          status: string | null
          submitted_at: string | null
          approved_by: string | null
          approved_at: string | null
          notes: string | null
          created_at: string | null
          manager_id: string | null
          manager_comment: string | null
          reimbursement_date: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      extourne_log: {
        Row: {
          id: string
          tenant_id: string | null
          original_entry_id: string
          extourne_entry_id: string
          extourne_date: string
          reason: string | null
          journal_code: string | null
          total_debit: number
          total_credit: number
          status: string
          created_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      fec_attestations: {
        Row: {
          id: string
          tenant_id: string | null
          fiscal_year_id: string
          attestation_number: string
          attestation_date: string
          fec_type: string
          entry_count: number
          total_debit: number
          total_credit: number
          file_name: string | null
          file_content: string | null
          status: string
          generated_by: string | null
          created_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      fiscal_backups: {
        Row: {
          id: string
          tenant_id: string | null
          fiscal_year_id: string | null
          backup_type: string
          status: string
          file_url: string | null
          file_size: string | null
          created_by: string | null
          created_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      fiscal_periods: {
        Row: {
          id: string
          fiscal_year_id: string | null
          period_number: number
          period_label: string
          start_date: string
          end_date: string
          status: string | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      fiscal_position_mappings: {
        Row: {
          id: string
          tenant_id: string | null
          fiscal_position_id: string
          source_tax_id: string | null
          target_tax_id: string | null
          source_account_code: string | null
          target_account_code: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      fiscal_positions: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          country_code: string | null
          country_group_id: string | null
          zip_from: string | null
          zip_to: string | null
          auto_apply: boolean | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      fiscal_years: {
        Row: {
          id: string
          code: string
          start_date: string
          end_date: string
          status: string | null
          closed_at: string | null
          closed_by: string | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      fixed_assets: {
        Row: {
          id: string
          name: string
          code: string | null
          category: string | null
          purchase_date: string
          purchase_value: number | null
          current_value: number | null
          depreciation_method: string | null
          useful_life_years: number | null
          residual_value: number | null
          status: string
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          asset_type: string | null
          parent_asset_id: string | null
          family_id: string | null
          asset_number: string | null
          lease_start_date: string | null
          lease_end_date: string | null
          lease_monthly_payment: number | null
          purchase_entry_id: string | null
          account_asset_code: string | null
          account_depreciation_code: string | null
          account_expense_depreciation_code: string | null
          journal_id: string | null
          partner_id: string | null
          currency_code: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      fusion_logs: {
        Row: {
          id: string
          tenant_id: string | null
          source_account_code: string
          target_account_code: string
          lines_moved: number
          fused_by: string | null
          fused_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      future_accounting_movements: {
        Row: {
          id: string
          tenant_id: string | null
          description: string
          account_code: string
          third_party_id: string | null
          amount: number
          movement_type: string
          expected_date: string
          source_type: string | null
          source_id: string | null
          incorporated: boolean | null
          incorporated_entry_id: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      goods_receipt_lines: {
        Row: {
          id: string
          goods_receipt_id: string | null
          product_id: string | null
          description: string
          quantity_ordered: number | null
          quantity_received: number | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      goods_receipts: {
        Row: {
          id: string
          number: string
          supplier_id: string | null
          purchase_order_id: string | null
          receipt_date: string
          status: string
          notes: string | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      grid_templates: {
        Row: {
          id: string
          tenant_id: string | null
          code: string
          name: string
          description: string | null
          journal_code: string | null
          columns_config: Record<string, any>
          default_account: string | null
          is_active: boolean | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      honorarium_records: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string | null
          recipient_name: string
          recipient_type: string | null
          period: string | null
          amount: number
          description: string | null
          accounting_entry_id: string | null
          status: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      ifrs_adjustments: {
        Row: {
          id: string
          tenant_id: string | null
          fiscal_year_id: string | null
          adjustment_type: string
          account_code: string
          counter_account_code: string
          description: string
          amount: number
          adjustment_date: string
          ifrs_standard: string | null
          journal_entry_id: string | null
          status: string
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      ijss_history: {
        Row: {
          id: string
          tenant_id: string | null
          work_stoppage_id: string
          employee_id: string
          period: string
          ijss_net_received: number | null
          ijss_brut_calculated: number | null
          days_paid: number | null
          pas_amount: number | null
          pas_rate: number | null
          integrated_in_payslip: boolean | null
          payslip_id: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      interview_campaigns: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          campaign_type: string
          start_date: string
          end_date: string | null
          reminder_days: number | null
          status: string | null
          form_template: Record<string, any> | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      interviews: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          type: string | null
          scheduled_date: string | null
          conducted_at: string | null
          conducted_by: string | null
          objectives: string | null
          feedback: string | null
          rating: number | null
          status: string | null
          created_at: string | null
          campaign_id: string | null
          form_data: Record<string, any> | null
          employee_feedback: string | null
          employee_rating: number | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      investments: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          type: string | null
          institution: string | null
          initial_amount: number
          current_value: number | null
          acquisition_date: string | null
          maturity_date: string | null
          interest_rate: number | null
          status: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      invoice_lines: {
        Row: {
          id: string
          invoice_id: string | null
          product_id: string | null
          description: string
          quantity: number | null
          unit_price: number | null
          vat_rate: number | null
          total: number | null
          vat_total: number | null
          line_order: number | null
          created_at: string | null
          tenant_id: string
          delivery_note_line_id: string | null
          sales_order_line_id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      invoices: {
        Row: {
          id: string
          number: string
          customer_id: string | null
          customer_name: string | null
          date: string
          due_date: string
          status: string
          subtotal: number | null
          vat_total: number | null
          total: number | null
          amount_paid: number | null
          amount_due: number | null
          notes: string | null
          recurring: boolean | null
          recurring_frequency: string | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          validation_status: string | null
          fiscal_position_id: string | null
          payment_state: string | null
          currency_code: string | null
          exchange_rate: number | null
          amount_untaxed_currency: number | null
          amount_tax_currency: number | null
          amount_total_currency: number | null
          delivery_note_id: string | null
          sales_order_id: string | null
          quote_id: string | null
          is_advance_invoice: boolean | null
          advance_amount: number | null
          invoice_type: string | null
          parent_invoice_id: string | null
          transferred_entry_id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      journal_access_rights: {
        Row: {
          id: string
          tenant_id: string | null
          user_id: string
          journal_code: string
          can_view: boolean
          can_create: boolean
          can_edit: boolean
          can_delete: boolean
          can_close: boolean
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      journal_entries: {
        Row: {
          id: string
          number: string
          date: string
          description: string
          reference: string | null
          status: string
          total_debit: number | null
          total_credit: number | null
          created_at: string | null
          updated_at: string | null
          journal_code: string | null
          fiscal_period_id: string | null
          piece_number: string | null
          invoice_ref: string | null
          entry_template_id: string | null
          status_detail: string | null
          validated_by: string | null
          validated_at: string | null
          tenant_id: string
          ifrs_mode: boolean | null
          currency_code: string | null
          functional_currency: string | null
          exchange_rate: number | null
          exchange_rate_date: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      journal_lines: {
        Row: {
          id: string
          journal_id: string | null
          account_code: string
          account_name: string | null
          debit: number | null
          credit: number | null
          description: string | null
          line_order: number | null
          created_at: string | null
          account_general: string | null
          account_tiers: string | null
          third_party_id: string | null
          lettrage_code: string | null
          lettrage_date: string | null
          piece_number: string | null
          reference: string | null
          analytic_section_id: string | null
          analytic_amount: number | null
          running_balance: number | null
          reconciled: boolean | null
          line_date: string | null
          tenant_id: string
          vat_code: string | null
          vat_amount: number | null
          echeance_date: string | null
          quantity: number | null
          marking_code: string | null
          marked_bap: boolean | null
          marked_bap_date: string | null
          tax_tag_ids: string | null
          analytic_distribution: Record<string, any> | null
          amount_residual: number | null
          product_id: string | null
          product_uom: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      journals: {
        Row: {
          id: string
          code: string
          name: string
          type: string
          account_counterpart: string | null
          bank_account_id: string | null
          default_entry_template_id: string | null
          status: string | null
          locked: boolean | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          access_level: string | null
          numbering_mode: string | null
          account_attente: string | null
          is_analytic: boolean | null
          analytic_plan_id: string | null
          currency_code: string | null
          sequence: number | null
          next_number: number | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      justificatif_solde: {
        Row: {
          id: string
          tenant_id: string | null
          account_code: string
          third_party_code: string | null
          fiscal_period_id: string | null
          opening_balance: number
          total_debit: number
          total_credit: number
          closing_balance: number
          generated_at: string
          generated_by: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      knowledge_base_articles: {
        Row: {
          id: string
          tenant_id: string | null
          title: string
          category: string | null
          content: string
          tags: string | null
          author: string | null
          status: string | null
          views: number | null
          helpful_count: number | null
          not_helpful_count: number | null
          is_public: boolean | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      leave_balances: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          leave_type: string
          year: number
          acquired: number | null
          taken: number | null
          pending: number | null
          remaining: number | null
          carry_over: number | null
          provision: number | null
          provision_calculated_at: string | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      leave_provisions: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          period: string
          cp_remaining_days: number | null
          rtt_remaining_days: number | null
          recovery_remaining_days: number | null
          daily_rate: number | null
          cp_provision: number | null
          rtt_provision: number | null
          recovery_provision: number | null
          total_provision: number | null
          accounting_entry_id: string | null
          status: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      leave_requests: {
        Row: {
          id: string
          employee_id: string
          leave_type: string
          start_date: string
          end_date: string
          days: number | null
          status: string
          reason: string | null
          approved_by: string | null
          approved_at: string | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      leave_rules: {
        Row: {
          id: string
          tenant_id: string | null
          leave_type: string
          label: string
          accrual_rate: number | null
          max_carry_over: number | null
          carry_over_expiry_months: number | null
          requires_justification: boolean | null
          requires_manager_approval: boolean | null
          min_notice_days: number | null
          max_consecutive_days: number | null
          color: string | null
          count_method: string | null
          affects_pay: boolean | null
          deduction_rate: number | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      legal_declarations: {
        Row: {
          id: string
          number: string
          declaration_type: string
          period_month: number
          period_year: number
          due_date: string
          submission_date: string | null
          amount: number | null
          status: string
          notes: string | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      legal_watch: {
        Row: {
          id: string
          tenant_id: string | null
          title: string
          category: string | null
          source: string | null
          summary: string | null
          content_url: string | null
          published_date: string | null
          relevance: string | null
          read: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      legislation_packs: {
        Row: {
          code: string
          name: string
          country_code: string
          country_name: string
          accounting_standard: string
          currency: string
          currency_decimals: number
          date_format: string
          locale: string
          fiscal_year_start: string
          tax_id_label: string
          tax_id_secondary_label: string | null
          is_default: boolean
          active: boolean
          created_at: string | null
          updated_at: string | null
          tenant_id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      lettrage_differences: {
        Row: {
          id: string
          tenant_id: string | null
          third_party_code: string
          lettrage_code: string
          line_id_1: string
          line_id_2: string
          debit_amount: number
          credit_amount: number
          difference: number
          difference_account: string | null
          generated_entry_id: string | null
          status: string
          created_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      machines: {
        Row: {
          id: string
          tenant_id: string | null
          code: string
          name: string
          work_center_id: string | null
          capacity_per_hour: number | null
          status: string | null
          purchase_date: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      manufacturing_orders: {
        Row: {
          id: string
          number: string
          bom_id: string | null
          product_id: string | null
          quantity: number
          status: string
          start_date: string | null
          end_date: string | null
          warehouse_id: string | null
          notes: string | null
          created_at: string | null
          tenant_id: string
          routing_id: string | null
          origin: string | null
          parent_mo_id: string | null
          lot_number: string | null
          expiry_date: string | null
          custom_expiry_date: string | null
          expiry_type: string | null
          label_enabled: boolean | null
          additional_text: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      marking_types: {
        Row: {
          id: string
          tenant_id: string | null
          code: string
          label: string
          color: string | null
          active: boolean | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      meal_voucher_config: {
        Row: {
          id: string
          tenant_id: string | null
          voucher_value: number
          employer_share: number | null
          employee_share: number | null
          eligible_days: string | null
          max_per_month: number | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      medical_exams: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          exam_type: string
          scheduled_date: string
          completed_date: string | null
          result: string | null
          restrictions: string | null
          next_exam_date: string | null
          occupational_doctor: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      mirror_servers: {
        Row: {
          id: string
          machine_id: string
          machine_name: string
          os: string | null
          ip_address: string | null
          mirror_dir: string | null
          registered_at: string | null
          last_heartbeat: string | null
          status: string
          config: Record<string, any> | null
          install_status: string | null
          verification_data: Record<string, any> | null
          verified_at: string | null
          install_token: string | null
          install_platform: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      mirror_verification_details: {
        Row: {
          id: string
          mirror_server_id: string | null
          table_name: string
          cloud_rows: number
          local_rows: number
          match: boolean
          verified_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      module_document_access_log: {
        Row: {
          id: string
          tenant_id: string
          document_id: string
          user_id: string
          action: string
          ip_address: string | null
          user_agent: string | null
          created_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      module_document_shares: {
        Row: {
          id: string
          tenant_id: string
          document_id: string
          share_token: string
          password_hash: string | null
          created_by: string
          expires_at: string | null
          max_downloads: number | null
          download_count: number | null
          created_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      module_documents: {
        Row: {
          id: string
          tenant_id: string
          module: string
          document_type: string
          confidentiality: string
          entity_type: string | null
          entity_id: string | null
          title: string
          description: string | null
          file_url: string
          file_name: string
          file_size: string | null
          mime_type: string | null
          file_hash: string | null
          status: string
          approved_by: string | null
          approved_at: string | null
          rejection_reason: string | null
          expires_at: string | null
          archived_at: string | null
          uploaded_by: string
          metadata: Record<string, any> | null
          download_count: number | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      mrp_pending_docs: {
        Row: {
          id: string
          tenant_id: string | null
          doc_type: string
          doc_id: string | null
          product_id: string | null
          quantity: number | null
          status: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      mrp_proposals: {
        Row: {
          id: string
          tenant_id: string | null
          mrp_run_id: string
          product_id: string
          proposal_type: string | null
          gross_need: number
          stock_available: number | null
          open_orders: number | null
          net_need: number
          suggested_quantity: number | null
          suggested_date: string | null
          bom_id: string | null
          supplier_id: string | null
          status: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      mrp_runs: {
        Row: {
          id: string
          tenant_id: string | null
          run_number: string
          run_date: string | null
          status: string | null
          parameters: Record<string, any> | null
          summary: Record<string, any> | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      notification_email_queue: {
        Row: {
          id: string
          tenant_id: string | null
          recipient_email: string
          recipient_name: string | null
          notification_type: string
          subject: string
          status: string | null
          resend_id: string | null
          error_message: string | null
          sent_at: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      notification_preferences: {
        Row: {
          id: string
          tenant_id: string
          employee_id: string
          email_enabled: boolean | null
          email_types: Record<string, any> | null
          digest_mode: string | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      of_consumptions: {
        Row: {
          id: string
          tenant_id: string | null
          manufacturing_order_id: string
          product_id: string
          quantity: number
          unit: string | null
          consumption_date: string
          is_deferred: boolean | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      of_document_access: {
        Row: {
          id: string
          tenant_id: string | null
          user_id: string
          document_type: string
          can_view: boolean | null
          can_print: boolean | null
          can_export: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      of_labels: {
        Row: {
          id: string
          tenant_id: string | null
          manufacturing_order_id: string
          label_number: string
          product_id: string | null
          planned_quantity: number | null
          actual_quantity: number | null
          is_complete: boolean | null
          is_declared: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      of_lots: {
        Row: {
          id: string
          tenant_id: string | null
          manufacturing_order_id: string
          lot_number: string
          product_id: string | null
          quantity: number | null
          production_date: string | null
          expiry_date: string | null
          custom_expiry_date: string | null
          expiry_type: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      online_payments: {
        Row: {
          id: string
          tenant_id: string | null
          invoice_id: string | null
          customer_id: string | null
          payment_provider: string | null
          provider_transaction_id: string | null
          amount: number
          currency_code: string | null
          status: string | null
          payment_url: string | null
          paid_at: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      partner_bank_accounts: {
        Row: {
          id: string
          tenant_id: string | null
          partner_type: string
          partner_id: string
          account_number: string
          bank_name: string | null
          bic: string | null
          bank_code: string | null
          sort_code: string | null
          account_key: string | null
          currency_code: string | null
          is_default: boolean | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      partner_categories: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          color: string | null
          parent_id: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      partner_category_mappings: {
        Row: {
          id: string
          tenant_id: string | null
          category_id: string
          partner_type: string
          partner_id: string
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      partner_contacts: {
        Row: {
          id: string
          tenant_id: string | null
          partner_type: string
          partner_id: string
          contact_type: string
          name: string
          email: string | null
          phone: string | null
          mobile: string | null
          function: string | null
          address: string | null
          postal_code: string | null
          city: string | null
          country: string | null
          is_default: boolean | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      pas_rates: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          rate: number
          effective_date: string
          expiry_date: string | null
          source: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      pay_recalls: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          reference_period: string
          recall_amount: number
          reason: string | null
          status: string | null
          processed_pay_run_id: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      pay_runs: {
        Row: {
          id: string
          number: string
          period_start: string
          period_end: string
          pay_date: string
          status: string
          gross_total: number | null
          tax_total: number | null
          net_total: number | null
          employee_count: number | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      pay_slip_clarified: {
        Row: {
          id: string
          tenant_id: string | null
          pay_slip_id: string
          employee_id: string
          period: string
          gross_salary: number | null
          social_charges_employee: number | null
          social_charges_employer: number | null
          income_tax: number | null
          net_before_tax: number | null
          net_after_tax: number | null
          total_deductions: number | null
          lines: Record<string, any> | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      pay_slips: {
        Row: {
          id: string
          number: string
          pay_run_id: string | null
          employee_id: string
          period_start: string
          period_end: string
          gross_salary: number | null
          overtime_pay: number | null
          bonus: number | null
          total_gross: number | null
          social_security_employee: number | null
          income_tax: number | null
          other_deductions: number | null
          total_deductions: number | null
          net_salary: number | null
          employer_contributions: number | null
          status: string
          payment_date: string | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      payment_orders: {
        Row: {
          id: string
          number: string
          type: string
          status: string
          bank_account_id: string | null
          third_party_id: string | null
          third_party_name: string | null
          third_party_iban: string | null
          amount: number
          payment_date: string
          reference: string | null
          description: string | null
          remise_number: string | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          currency_code: string | null
          exchange_rate: number | null
          amount_currency: number | null
          exchange_gain_loss: number | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      payment_promises: {
        Row: {
          id: string
          tenant_id: string | null
          third_party_code: string
          amount: number
          promised_date: string
          reminder_level: number | null
          status: string
          notes: string | null
          created_by: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      payment_templates_compta: {
        Row: {
          id: string
          tenant_id: string | null
          code: string
          name: string
          description: string | null
          payment_method: string
          day_count: number | null
          end_of_month: boolean | null
          is_active: boolean | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      payment_terms: {
        Row: {
          id: string
          tenant_id: string | null
          code: string
          name: string
          type: string
          days_1: number
          days_2: number | null
          pct_1: number | null
          pct_2: number | null
          end_of_month: boolean | null
          description: string | null
          active: boolean | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      payroll_accounting_entries: {
        Row: {
          id: string
          number: string
          pay_run_id: string | null
          period_date: string
          gross_total: number | null
          employer_contributions_total: number | null
          employee_deductions_total: number | null
          net_total: number | null
          journal_entry_id: string | null
          status: string
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      payroll_archives: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string | null
          period: string
          archive_type: string | null
          file_url: string
          file_encrypted: boolean | null
          retention_until: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      payroll_component_rates: {
        Row: {
          id: string
          tenant_id: string | null
          component_id: string
          legislation_pack: string | null
          rate_employer: number | null
          rate_employee: number | null
          ceiling_amount: number | null
          effective_date: string
          end_date: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      payroll_components: {
        Row: {
          id: string
          tenant_id: string | null
          code: string
          name: string
          type: string
          calculation_type: string | null
          default_value: number | null
          rate_employer: number | null
          rate_employee: number | null
          ceiling_amount: number | null
          ceiling_basis: string | null
          tax_deductible: boolean | null
          display_order: number | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      payroll_tax_grid_lines: {
        Row: {
          id: string
          grid_id: string
          line_type: string
          category: string
          label: string
          base_type: string
          min_amount: number | null
          max_amount: number | null
          rate_employee: number | null
          rate_employer: number | null
          cap_amount: number | null
          fixed_amount: number | null
          sort_order: number
          created_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      payroll_tax_grids: {
        Row: {
          id: string
          tenant_id: string | null
          country_code: string
          grid_type: string
          name: string
          description: string | null
          effective_from: string
          effective_to: string | null
          status: string
          source: string
          file_url: string | null
          is_default: boolean
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      payroll_templates: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          category: string | null
          component_ids: Record<string, any> | null
          description: string | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      payroll_variable_elements: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          pay_run_id: string | null
          period: string
          element_type: string
          description: string | null
          quantity: number | null
          unit_price: number | null
          amount: number
          source: string | null
          source_id: string | null
          integrated: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      pick_list_lines: {
        Row: {
          id: string
          tenant_id: string | null
          pick_list_id: string
          product_id: string
          location_id: string | null
          quantity_to_pick: number
          quantity_picked: number | null
          barcode: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      pick_lists: {
        Row: {
          id: string
          tenant_id: string | null
          number: string
          reference_type: string | null
          reference_id: string | null
          warehouse_id: string | null
          status: string | null
          picked_by: string | null
          picked_at: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      planning_slots: {
        Row: {
          id: string
          tenant_id: string | null
          manufacturing_order_id: string
          routing_operation_id: string | null
          machine_id: string | null
          work_center_id: string | null
          planned_start: string | null
          planned_end: string | null
          setup_time: number | null
          run_time: number | null
          status: string | null
          material_available: boolean | null
          material_check_date: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      pos_sessions: {
        Row: {
          id: string
          tenant_id: string | null
          terminal_id: string
          user_email: string
          opening_amount: number | null
          closing_amount: number | null
          expected_amount: number | null
          difference: number | null
          status: string | null
          opened_at: string | null
          closed_at: string | null
          notes: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      pos_terminals: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          warehouse_id: string | null
          location: string | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      pos_ticket_lines: {
        Row: {
          id: string
          tenant_id: string | null
          ticket_id: string
          product_id: string | null
          description: string
          quantity: number
          unit_price: number
          vat_rate: number | null
          line_total: number
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      pos_tickets: {
        Row: {
          id: string
          tenant_id: string | null
          number: string
          session_id: string
          terminal_id: string
          customer_id: string | null
          date: string | null
          subtotal: number | null
          vat_total: number | null
          total: number | null
          payment_method: string | null
          amount_paid: number | null
          change_given: number | null
          status: string | null
          invoice_id: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      price_list_lines: {
        Row: {
          id: string
          price_list_id: string | null
          product_id: string | null
          unit_price: number
          min_quantity: number | null
          discount_percent: number | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      price_lists: {
        Row: {
          id: string
          name: string
          code: string | null
          type: string
          currency: string | null
          valid_from: string | null
          valid_to: string | null
          active: boolean | null
          is_default: boolean | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      product_attributes: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          type: string
          options: Record<string, any> | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      product_batches: {
        Row: {
          id: string
          tenant_id: string | null
          product_id: string
          batch_number: string
          quantity: number
          expiry_date: string | null
          status: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      product_equivalences: {
        Row: {
          id: string
          tenant_id: string | null
          product_id: string
          equivalent_product_id: string
          conversion_ratio: number | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      product_grid_combinations: {
        Row: {
          id: string
          tenant_id: string | null
          product_id: string
          combination: Record<string, any>
          sku: string | null
          barcode: string | null
          price_override: number | null
          stock_quantity: number | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      product_grids: {
        Row: {
          id: string
          tenant_id: string | null
          product_id: string
          name: string
          axis: string
          values: Record<string, any>
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      product_links: {
        Row: {
          id: string
          tenant_id: string | null
          product_id: string
          linked_product_id: string
          link_type: string
          quantity: number | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      product_packagings: {
        Row: {
          id: string
          tenant_id: string | null
          product_id: string
          name: string
          quantity: number
          unit: string | null
          barcode: string | null
          weight: number | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      product_serial_numbers: {
        Row: {
          id: string
          tenant_id: string | null
          product_id: string
          serial_number: string
          status: string | null
          warranty_expiry: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      product_substitutes: {
        Row: {
          id: string
          tenant_id: string | null
          product_id: string
          substitute_id: string
          priority: number | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      product_variants: {
        Row: {
          id: string
          tenant_id: string | null
          product_id: string
          sku: string
          attributes: Record<string, any> | null
          price_override: number | null
          barcode: string | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      production_forecasts: {
        Row: {
          id: string
          tenant_id: string | null
          forecast_number: string
          period: string
          start_date: string
          end_date: string
          product_id: string | null
          forecasted_quantity: number
          actual_quantity: number | null
          reliability_rate: number | null
          source: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      products: {
        Row: {
          id: string
          name: string
          sku: string | null
          description: string | null
          type: string
          sale_price: number | null
          purchase_price: number | null
          vat_rate: number | null
          stock_quantity: number | null
          reorder_level: number | null
          unit: string | null
          category: string | null
          active: boolean | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          is_amalgam: boolean | null
          units_per_carton: number | null
          st_unit: string | null
          purchase_unit: string | null
          st_multiple: number | null
          shelf_life_days: number | null
          exclude_from_mrp: boolean | null
          barcode: string | null
          weight: number | null
          photo_url: string | null
          supplier_ref: string | null
          criticality_level: string | null
          cost_price: number | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      project_activity_log: {
        Row: {
          id: string
          tenant_id: string
          task_id: string | null
          project_id: string | null
          user_id: string | null
          user_name: string | null
          action_type: string
          old_value: Record<string, any> | null
          new_value: Record<string, any> | null
          description: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      project_docs: {
        Row: {
          id: string
          tenant_id: string
          project_id: string | null
          title: string
          content: string
          created_by: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      project_members: {
        Row: {
          id: string
          tenant_id: string
          project_id: string
          employee_id: string
          role: string
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      project_milestones: {
        Row: {
          id: string
          tenant_id: string
          project_id: string
          name: string
          deadline: string | null
          is_reached: boolean | null
          is_reached_manually: boolean | null
          sale_line_id: string | null
          sale_line_qty_percentage: number | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      project_notifications: {
        Row: {
          id: string
          tenant_id: string
          recipient_id: string
          task_id: string | null
          project_id: string | null
          notification_type: string
          title: string
          message: string | null
          is_read: boolean | null
          action_url: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      project_stages: {
        Row: {
          id: string
          tenant_id: string
          name: string
          sequence: number | null
          fold: boolean | null
          case_default: boolean | null
          mail_template_id: string | null
          legend_priority: string | null
          legend_blocked: string | null
          legend_done: string | null
          legend_normal: string | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      project_tags: {
        Row: {
          id: string
          tenant_id: string
          name: string
          color: number | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      project_task_assignees: {
        Row: {
          task_id: string
          employee_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      project_task_dependencies: {
        Row: {
          id: string
          tenant_id: string
          task_id: string
          depends_on_task_id: string
          dependency_type: string
          lag_days: number | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      project_task_tags: {
        Row: {
          task_id: string
          tag_id: string
          tenant_id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      project_task_templates: {
        Row: {
          id: string
          tenant_id: string
          name: string
          description: string | null
          default_status: string | null
          default_priority: string | null
          default_assignee_id: string | null
          default_tags: string | null
          default_effort_estimate: number | null
          default_budget: number | null
          checklist_template: Record<string, any> | null
          subtasks_template: Record<string, any> | null
          is_public: boolean | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      project_task_watchers: {
        Row: {
          id: string
          tenant_id: string
          task_id: string
          employee_id: string
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      project_tasks: {
        Row: {
          id: string
          tenant_id: string
          project_id: string | null
          parent_id: string | null
          title: string
          description: string | null
          status: string
          priority: string
          assignee: string | null
          start_date: string | null
          due_date: string | null
          effort_estimate_h: number | null
          effort_spent_h: number | null
          progress: number | null
          display_order: string
          task_level: number | null
          budget: number | null
          color: number | null
          acceptance_criteria: string | null
          recurring_task: boolean | null
          recurring_interval: number | null
          recurring_rule_type: string | null
          is_closed: boolean | null
          linked_action_id: string | null
          created_at: string | null
          updated_at: string | null
          assignee_id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      project_time_entries: {
        Row: {
          id: string
          tenant_id: string
          task_id: string | null
          project_id: string | null
          employee_id: string | null
          start_time: string
          end_time: string | null
          duration_seconds: number | null
          description: string | null
          is_billable: boolean | null
          hourly_rate: number | null
          tags: string | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      projects: {
        Row: {
          id: string
          name: string
          description: string | null
          customer_id: string | null
          status: string
          budget: number | null
          actual_cost: number | null
          start_date: string | null
          end_date: string | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          color: string | null
          display_order: string | null
          progress: number | null
          manager_id: string | null
          allow_subtasks: boolean | null
          allow_recurrent_tasks: boolean | null
          allow_milestones: boolean | null
          allow_task_dependencies: boolean | null
          allow_timesheets: boolean | null
          allow_billable: boolean | null
          privacy_visibility: string | null
          alias_name: string | null
          allocated_hours: number | null
          total_hours_spent: number | null
          remaining_hours: number | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      promotions: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          description: string | null
          promo_type: string
          value: number | null
          product_id: string | null
          category: string | null
          customer_id: string | null
          start_date: string
          end_date: string
          min_quantity: number | null
          free_product_id: string | null
          free_product_qty: number | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      prospects: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          email: string | null
          phone: string | null
          address: string | null
          city: string | null
          postal_code: string | null
          country: string | null
          contact_name: string | null
          source: string | null
          status: string | null
          assigned_rep_id: string | null
          notes: string | null
          converted_customer_id: string | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      public_holidays: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          holiday_date: string
          region: string | null
          country: string | null
          is_working_day: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      purchase_credit_lines: {
        Row: {
          id: string
          purchase_credit_id: string | null
          description: string
          quantity: number | null
          unit_price: number | null
          vat_rate: number | null
          total: number | null
          vat_total: number | null
          line_order: number | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      purchase_credit_notes: {
        Row: {
          id: string
          number: string
          supplier_id: string | null
          supplier_name: string | null
          date: string
          status: string
          subtotal: number | null
          vat_total: number | null
          total: number | null
          reason: string | null
          purchase_invoice_id: string | null
          created_at: string | null
          tenant_id: string
          currency_code: string | null
          exchange_rate: number | null
          amount_untaxed_currency: number | null
          amount_tax_currency: number | null
          amount_total_currency: number | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      purchase_invoice_lines: {
        Row: {
          id: string
          purchase_invoice_id: string | null
          product_id: string | null
          description: string
          quantity: number | null
          unit_price: number | null
          vat_rate: number | null
          total: number | null
          vat_total: number | null
          line_order: number | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      purchase_invoices: {
        Row: {
          id: string
          number: string
          supplier_id: string | null
          supplier_name: string | null
          date: string
          due_date: string
          status: string
          subtotal: number | null
          vat_total: number | null
          total: number | null
          amount_paid: number | null
          amount_due: number | null
          notes: string | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          approval_status: string | null
          approved_by: string | null
          approved_at: string | null
          fiscal_position_id: string | null
          payment_state: string | null
          currency_code: string | null
          exchange_rate: number | null
          amount_untaxed_currency: number | null
          amount_tax_currency: number | null
          amount_total_currency: number | null
          transferred_entry_id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      purchase_order_lines: {
        Row: {
          id: string
          purchase_order_id: string | null
          product_id: string | null
          description: string
          quantity: number
          unit_price: number
          vat_rate: number | null
          line_total: number | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      purchase_orders: {
        Row: {
          id: string
          number: string
          supplier_id: string | null
          order_date: string
          expected_date: string | null
          status: string
          subtotal: number | null
          vat: number | null
          total: number | null
          notes: string | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      purchase_request_lines: {
        Row: {
          id: string
          tenant_id: string | null
          purchase_request_id: string
          product_id: string | null
          description: string
          quantity: number
          unit: string | null
          estimated_price: number | null
          preferred_supplier_id: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      purchase_requests: {
        Row: {
          id: string
          tenant_id: string | null
          number: string
          requester: string | null
          department: string | null
          status: string | null
          priority: string | null
          expected_date: string | null
          notes: string | null
          approved_by: string | null
          approved_at: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      quality_checks: {
        Row: {
          id: string
          tenant_id: string | null
          product_id: string
          reference_type: string | null
          reference_id: string | null
          status: string | null
          checked_by: string | null
          checked_at: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      quote_lines: {
        Row: {
          id: string
          quote_id: string | null
          product_id: string | null
          description: string
          quantity: number | null
          unit_price: number | null
          vat_rate: number | null
          total: number | null
          vat_total: number | null
          line_order: number | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      quotes: {
        Row: {
          id: string
          number: string
          customer_id: string | null
          customer_name: string | null
          date: string
          expiry_date: string
          status: string
          subtotal: number | null
          vat_total: number | null
          total: number | null
          notes: string | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          validation_status: string | null
          transformed_to_order_id: string | null
          transformation_status: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      recurring_entries: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          description: string | null
          journal_id: string
          journal_code: string | null
          frequency: string
          day_of_month: number
          start_date: string
          end_date: string | null
          next_generation_date: string
          last_generation_date: string | null
          lines: Record<string, any>
          status: string
          total_debit: number
          total_credit: number
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      recurring_invoice_templates: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          customer_id: string | null
          frequency: string | null
          next_date: string
          lines: Record<string, any> | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      regularization_entries: {
        Row: {
          id: string
          tenant_id: string | null
          type: string
          fiscal_year_id: string | null
          account_code: string
          third_party_code: string | null
          description: string
          invoice_number: string | null
          invoice_date: string | null
          invoice_amount: number
          start_date: string
          end_date: string
          amount: number
          used_amount: number
          remaining_amount: number
          status: string
          journal_id: string | null
          journal_code: string | null
          created_entry_id: string | null
          extourne_entry_id: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      reimputation_logs: {
        Row: {
          id: string
          tenant_id: string | null
          original_entry_id: string | null
          original_line_id: string | null
          reimputed_entry_id: string | null
          reimputed_line_id: string | null
          from_account: string
          to_account: string
          amount: number
          reason: string | null
          status: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      reminder_levels: {
        Row: {
          id: string
          tenant_id: string | null
          level: number
          name: string
          template: string | null
          days_after_due: number
          penalty_rate: number | null
          active: boolean | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      reporting_plans: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          report_type: string
          schedule: string
          format: string
          recipients: string | null
          parameters: Record<string, any> | null
          last_generated: string | null
          active: boolean | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      revision_cycles: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          frequency: string
          start_month: number
          account_class: string | null
          active: boolean | null
          last_run: string | null
          next_run: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      rgpd_requests: {
        Row: {
          id: string
          tenant_id: string | null
          request_type: string
          entity_type: string
          entity_id: string | null
          status: string
          requested_by: string | null
          processed_by: string | null
          requested_at: string
          processed_at: string | null
          notes: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      rh_dashboard_configs: {
        Row: {
          id: string
          tenant_id: string | null
          user_email: string
          dashboard_type: string
          widgets: Record<string, any> | null
          filters: Record<string, any> | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      rh_knowledge_base: {
        Row: {
          id: string
          tenant_id: string | null
          title: string
          content: string
          category: string | null
          tags: string | null
          author_id: string | null
          published: boolean | null
          views: number | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      rh_reports: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          report_type: string
          parameters: Record<string, any> | null
          chart_type: string | null
          data: Record<string, any> | null
          data_calculated_at: string | null
          created_by: string | null
          shared: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      rh_requests: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          request_type: string
          subject: string
          description: string | null
          status: string | null
          assigned_to: string | null
          response: string | null
          resolved_at: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      routing_operations: {
        Row: {
          id: string
          tenant_id: string | null
          routing_id: string
          sequence: number
          name: string
          description: string | null
          work_center_id: string | null
          machine_id: string | null
          tooling_id: string | null
          setup_time_min: number | null
          run_time_min: number | null
          is_subcontracted: boolean | null
          supplier_id: string | null
          st_unit: string | null
          st_quantity: number | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      routings: {
        Row: {
          id: string
          tenant_id: string | null
          code: string
          name: string
          description: string | null
          product_id: string | null
          version: number | null
          active: boolean | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      salary_advances: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          amount: number
          advance_date: string
          deduction_month: string | null
          status: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      sales_order_lines: {
        Row: {
          id: string
          sales_order_id: string | null
          product_id: string | null
          description: string
          quantity: number
          unit_price: number
          vat_rate: number | null
          line_total: number | null
          tenant_id: string
          delivered_quantity: number | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      sales_orders: {
        Row: {
          id: string
          number: string
          customer_id: string | null
          order_date: string
          delivery_date: string | null
          status: string
          subtotal: number | null
          vat: number | null
          total: number | null
          notes: string | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          validation_status: string | null
          quote_id: string | null
          fully_delivered: boolean | null
          delivery_status: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      sales_representatives: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          email: string | null
          phone: string | null
          commission_rate: number | null
          territory: string | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      saved_filters: {
        Row: {
          id: string
          tenant_id: string | null
          user_email: string
          page_name: string
          filter_name: string
          filter_criteria: Record<string, any>
          is_default: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      sepa_payment_orders: {
        Row: {
          id: string
          tenant_id: string | null
          pay_run_id: string | null
          number: string
          execution_date: string
          total_amount: number
          currency: string | null
          employee_count: number | null
          file_url: string | null
          file_generated_at: string | null
          status: string | null
          transmitted_at: string | null
          processed_at: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      service_contracts: {
        Row: {
          id: string
          tenant_id: string | null
          number: string
          customer_id: string
          name: string
          contract_type: string | null
          start_date: string
          end_date: string | null
          status: string | null
          sla_response_hours: number | null
          sla_resolution_hours: number | null
          coverage: string | null
          max_tickets: number | null
          used_tickets: number | null
          amount: number | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      service_ticket_messages: {
        Row: {
          id: string
          tenant_id: string | null
          ticket_id: string
          author: string
          author_type: string
          message: string
          attachments: Record<string, any> | null
          is_internal: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      service_tickets: {
        Row: {
          id: string
          tenant_id: string | null
          number: string
          customer_id: string
          contact_id: string | null
          subject: string
          description: string | null
          category: string | null
          priority: string | null
          status: string | null
          assigned_to: string | null
          sla_due_date: string | null
          first_response_at: string | null
          resolved_at: string | null
          closed_at: string | null
          satisfaction_rating: number | null
          satisfaction_comment: string | null
          tags: string | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      social_declarations: {
        Row: {
          id: string
          tenant_id: string | null
          number: string
          declaration_type: string
          subtype: string | null
          period_month: number | null
          period_year: number | null
          period: string | null
          due_date: string | null
          status: string | null
          file_url: string | null
          file_format: string | null
          generated_at: string | null
          transmitted_at: string | null
          response_code: string | null
          response_message: string | null
          anomalies: Record<string, any> | null
          amount: number | null
          employee_count: number | null
          details: Record<string, any> | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      sql_migrations_tracker: {
        Row: {
          id: number
          filename: string
          executed_at: string | null
          status: string | null
          error_message: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      st_orders: {
        Row: {
          id: string
          tenant_id: string | null
          number: string
          supplier_id: string
          manufacturing_order_id: string | null
          routing_operation_id: string | null
          product_id: string | null
          quantity: number
          unit: string | null
          unit_price: number | null
          total_price: number | null
          status: string | null
          order_date: string
          expected_date: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      st_receipt_lines: {
        Row: {
          id: string
          tenant_id: string | null
          st_receipt_id: string
          product_id: string
          quantity: number
          unit: string | null
          line_type: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      st_receipts: {
        Row: {
          id: string
          tenant_id: string | null
          number: string
          st_order_id: string
          receipt_date: string
          warehouse_id: string | null
          quantity_received: number | null
          quantity_returned: number | null
          status: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      st_shipment_lines: {
        Row: {
          id: string
          tenant_id: string | null
          st_shipment_id: string
          product_id: string
          quantity: number
          unit: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      st_shipments: {
        Row: {
          id: string
          tenant_id: string | null
          number: string
          st_order_id: string
          shipment_date: string
          warehouse_id: string | null
          status: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      staff_requirements: {
        Row: {
          id: string
          tenant_id: string | null
          department: string
          min_staff: number
          days_of_week: string | null
          start_date: string | null
          end_date: string | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      standard_labels: {
        Row: {
          id: string
          label: string
          category: string | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      stat_fields: {
        Row: {
          id: string
          tenant_id: string | null
          entity_type: string
          entity_id: string
          field_name: string
          field_value: string | null
          field_type: string
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      stock_alerts: {
        Row: {
          id: string
          tenant_id: string | null
          product_id: string
          warehouse_id: string | null
          alert_type: string
          threshold: number | null
          current_value: number | null
          status: string | null
          triggered_at: string | null
          resolved_at: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      stock_movements: {
        Row: {
          id: string
          product_id: string | null
          type: string | null
          quantity: number
          reference: string | null
          date: string
          created_at: string | null
          warehouse_id: string | null
          movement_type: string | null
          unit_cost: number | null
          reference_type: string | null
          reference_id: string | null
          movement_date: string | null
          notes: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      stock_quantities: {
        Row: {
          id: string
          product_id: string
          warehouse_id: string
          quantity: number
          reserved_quantity: number
          min_quantity: number | null
          max_quantity: number | null
          reorder_point: number | null
          unit_cost: number | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          location_id: string | null
          incoming_quantity: number | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      supplier_contacts: {
        Row: {
          id: string
          tenant_id: string | null
          supplier_id: string
          name: string
          role: string | null
          email: string | null
          phone: string | null
          mobile: string | null
          is_default: boolean | null
          active: boolean | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      supplier_delivery_schedules: {
        Row: {
          id: string
          tenant_id: string | null
          supplier_id: string
          product_id: string
          warehouse_id: string | null
          frequency: string
          monday_qty: number | null
          tuesday_qty: number | null
          wednesday_qty: number | null
          thursday_qty: number | null
          friday_qty: number | null
          saturday_qty: number | null
          sunday_qty: number | null
          start_date: string
          end_date: string | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      supplier_payments: {
        Row: {
          id: string
          number: string
          supplier_id: string | null
          purchase_invoice_id: string | null
          payment_date: string
          amount: number
          method: string | null
          bank_account_id: string | null
          reference: string | null
          status: string
          created_at: string | null
          tenant_id: string
          currency_code: string | null
          exchange_rate: number | null
          amount_currency: number | null
          exchange_gain_loss: number | null
          transferred_entry_id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      supplier_price_list_lines: {
        Row: {
          id: string
          tenant_id: string | null
          price_list_id: string
          product_id: string
          supplier_ref: string | null
          unit_price: number
          min_quantity: number | null
          discount_percent: number | null
          lead_time_days: number | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      supplier_price_lists: {
        Row: {
          id: string
          tenant_id: string | null
          supplier_id: string
          name: string
          valid_from: string
          valid_to: string | null
          currency_code: string | null
          min_quantity: number | null
          discount_percent: number | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      suppliers: {
        Row: {
          id: string
          name: string
          email: string | null
          phone: string | null
          address: string | null
          city: string | null
          postal_code: string | null
          country: string | null
          vat_number: string | null
          contact_name: string | null
          balance: number | null
          payment_terms: string | null
          currency: string | null
          active: boolean | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          legal_form: string | null
          ape_code: string | null
          naf_code: string | null
          employee_count_range: string | null
          revenue_range: string | null
          payment_delay_avg: number | null
          siret: string | null
          sector_code: string | null
          geographic_zone: string | null
          parent_id: string | null
          is_company: boolean | null
          sales_rep_id: string | null
          currency_code: string | null
          bank_account_id: string | null
          price_list_id: string | null
          email_settings: Record<string, any> | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      task_action_attachments: {
        Row: {
          id: string
          tenant_id: string
          task_action_id: string
          task_id: string
          file_name: string
          file_path: string
          file_size: string | null
          mime_type: string | null
          uploader_id: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      task_actions: {
        Row: {
          id: string
          tenant_id: string
          task_id: string
          title: string
          weight_percentage: number | null
          is_done: boolean | null
          due_date: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      task_comments: {
        Row: {
          id: string
          tenant_id: string
          task_id: string
          content: string
          comment_type: string | null
          author_id: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      task_documents: {
        Row: {
          id: string
          tenant_id: string
          task_id: string
          project_id: string | null
          file_name: string
          file_path: string
          file_size: string | null
          mime_type: string | null
          uploader_id: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      tax_cash_basis_entries: {
        Row: {
          id: string
          tenant_id: string | null
          tax_id: string | null
          payment_id: string | null
          journal_entry_id: string | null
          base_amount: number | null
          tax_amount: number | null
          transition_date: string | null
          status: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      tax_groups: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          country_code: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      tax_payments: {
        Row: {
          id: string
          tenant_id: string | null
          payment_number: string
          tax_type: string
          period_label: string
          period_start: string
          period_end: string
          amount: number
          payment_date: string
          payment_method: string
          bank_account_id: string | null
          status: string
          confirmation_number: string | null
          journal_entry_id: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      tax_rates: {
        Row: {
          id: string
          pack_code: string
          name: string
          category: string
          rate: number
          account_code: string | null
          is_default: boolean
          effective_from: string
          effective_to: string | null
          created_at: string | null
          tenant_id: string | null
          account_collectee: string | null
          account_deductible: string | null
          type: string | null
          mode: string | null
          amount_type: string | null
          type_tax_use: string | null
          sequence: number | null
          parent_tax_id: string | null
          tax_exigibility: string | null
          cash_basis_transition_account: string | null
          price_include: boolean | null
          include_base_amount: boolean | null
          is_base_affected: boolean | null
          analytic: boolean | null
          fixed_amount: number | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      tax_repartition_lines: {
        Row: {
          id: string
          tenant_id: string | null
          tax_id: string
          document_type: string
          repartition_type: string
          factor: number | null
          account_code: string | null
          tag_ids: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      tenant_users: {
        Row: {
          id: string
          tenant_id: string
          auth_id: string | null
          email: string
          name: string
          role: string
          permissions: Record<string, any> | null
          status: string
          invited_by: string | null
          invited_at: string | null
          accepted_at: string | null
          last_login: string | null
          created_at: string | null
          updated_at: string | null
          valid_from: string | null
          valid_until: string | null
          module_roles: Record<string, any> | null
          guest_permissions: Record<string, any> | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      tenants: {
        Row: {
          id: string
          name: string
          legal_name: string | null
          siren: string | null
          siret: string | null
          vat_number: string | null
          address: string | null
          city: string | null
          postal_code: string | null
          country: string | null
          currency: string | null
          phone: string | null
          email: string | null
          logo_url: string | null
          status: string
          plan: string
          trial_ends_at: string | null
          created_at: string | null
          updated_at: string | null
          country_code: string | null
          legislation_pack_code: string | null
          enabled_modules: Record<string, any>
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      third_party_accounts: {
        Row: {
          id: string
          code: string
          account_general_code: string | null
          type: string
          name: string
          customer_id: string | null
          supplier_id: string | null
          employee_id: string | null
          balance: number | null
          lettrage_code: string | null
          currency: string | null
          active: boolean | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string
          payment_term_id: string | null
          default_bank_account_id: string | null
          credit_limit: number | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      tier_ribs: {
        Row: {
          id: string
          tenant_id: string | null
          third_party_account_id: string
          rib_label: string
          iban: string
          bic: string | null
          bank_name: string | null
          bank_code: string | null
          branch_code: string | null
          account_number: string | null
          key: string | null
          is_default: boolean
          active: boolean
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      timesheets: {
        Row: {
          id: string
          employee_id: string | null
          date: string
          hours: number | null
          description: string | null
          project_id: string | null
          status: string
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      toolings: {
        Row: {
          id: string
          tenant_id: string | null
          code: string
          name: string
          machine_id: string | null
          max_pieces: number | null
          initial_counter: number | null
          current_counter: number | null
          status: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      treasury_recurring: {
        Row: {
          id: string
          tenant_id: string | null
          description: string
          bank_account_id: string | null
          amount: number
          type: string
          frequency: string | null
          next_date: string
          end_date: string | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      treasury_transfers: {
        Row: {
          id: string
          tenant_id: string | null
          number: string
          from_account_id: string
          to_account_id: string
          amount: number
          transfer_date: string
          value_date: string | null
          status: string | null
          journal_entry_id: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      tvs_declarations: {
        Row: {
          id: string
          tenant_id: string | null
          fiscal_year: number
          vehicle_registration: string
          vehicle_type: string | null
          co2_emissions: number | null
          first_registration_date: string | null
          amount_co2: number | null
          amount_age: number | null
          amount_total: number | null
          status: string | null
          filed_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      users: {
        Row: {
          id: string
          auth_id: string | null
          name: string
          email: string
          role: string
          active: boolean | null
          last_login: string | null
          created_at: string | null
          updated_at: string | null
          tenant_id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      v_tenant_id: {
        Row: {
          id: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      value_date_tracking: {
        Row: {
          id: string
          tenant_id: string | null
          bank_account_id: string
          transaction_id: string | null
          operation_date: string
          value_date: string
          amount: number
          transaction_type: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      vat_on_collections: {
        Row: {
          id: string
          tenant_id: string | null
          fiscal_year_id: string | null
          period_label: string
          period_start: string
          period_end: string
          vat_base: number
          vat_rate: number
          vat_amount: number
          collected_amount: number
          uncollected_amount: number
          vat_collected: number
          vat_uncollected: number
          status: string
          journal_entry_id: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      vat_returns: {
        Row: {
          id: string
          period_start: string
          period_end: string
          status: string
          box1_output_vat: number | null
          box2_input_vat: number | null
          box3_vat_due: number | null
          box4_repayment_due: number | null
          box5_net_vat: number | null
          total_sales: number | null
          total_purchases: number | null
          submitted_date: string | null
          created_at: string | null
          tenant_id: string
          edi_tva_id: string | null
          edi_status: string | null
          edi_submitted_at: string | null
          edi_acknowledgment: string | null
          edi_acknowledged_at: string | null
          deposits_vat_collected: number | null
          deposits_vat_deductible: number | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      warehouse_locations: {
        Row: {
          id: string
          tenant_id: string | null
          warehouse_id: string
          zone: string | null
          aisle: string | null
          shelf: string | null
          code: string
          description: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      warehouse_users: {
        Row: {
          id: string
          tenant_id: string | null
          warehouse_id: string
          user_email: string
          role: string | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      warehouses: {
        Row: {
          id: string
          code: string
          name: string
          address: string | null
          city: string | null
          postal_code: string | null
          country: string | null
          active: boolean | null
          created_at: string | null
          tenant_id: string
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      work_centers: {
        Row: {
          id: string
          tenant_id: string | null
          code: string
          name: string
          capacity_hours_per_day: number | null
          cost_per_hour: number | null
          active: boolean | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      work_hardship: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          exposure_type: string
          exposure_level: string | null
          start_date: string | null
          end_date: string | null
          points: number | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      work_hardship_records: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          exposure_type: string
          exposure_level: string
          exposure_start: string | null
          exposure_end: string | null
          duration_months: number | null
          points: number | null
          declaration_status: string | null
          declared_at: string | null
          notes: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      work_stoppages: {
        Row: {
          id: string
          tenant_id: string | null
          employee_id: string
          stoppage_type: string
          start_date: string
          end_date: string | null
          expected_end_date: string | null
          reprise_date: string | null
          reprise_type: string | null
          days_count: number | null
          working_days_count: number | null
          subrogation: boolean | null
          net_guarantee: boolean | null
          ijss_net_amount: number | null
          ijss_brut_amount: number | null
          ijss_daily_rate: number | null
          ijss_days_count: number | null
          ijss_care_days: number | null
          pas_days_count: number | null
          employer_maintenance_amount: number | null
          employer_maintenance_rate: number | null
          bpij_number: string | null
          bpij_imported_at: string | null
          regularization_amount: number | null
          regularization_type: string | null
          medical_certificate_url: string | null
          notes: string | null
          status: string | null
          created_at: string | null
          updated_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
      workflows: {
        Row: {
          id: string
          tenant_id: string | null
          name: string
          description: string | null
          workflow_type: string | null
          schedule: string | null
          last_run: string | null
          status: string | null
          created_at: string | null
        }
        Insert: Record<string, any>
        Update: Record<string, any>
      }
    }
    Functions: Record<string, any>
  }
}
