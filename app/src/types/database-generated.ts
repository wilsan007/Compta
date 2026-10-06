// ============================================
// Types générés automatiquement depuis PostgreSQL
// NE PAS ÉDITER MANUELLEMENT — utiliser scripts/generate-db-types.mjs
// ============================================

// LOT7-04 : les colonnes json/jsonb étaient typées `any`, ce qui désactivait
// tout contrôle sur leur contenu ET sur tout ce qu'on en dérivait. `Json` décrit
// la forme réelle d'une valeur JSON : le compilateur exige désormais un accès
// explicite (cast ou garde de type) au lieu de laisser passer n'importe quoi.
export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export interface Database {
  public: {
    Tables: {
    absence_conflict_log: {
      Row: {
        id: string
        tenant_id: string
        employee_id: string
        day: string
        kept_kind: string
        kept_origin: string
        dropped_kind: string
        dropped_origin: string
        detected_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        day: string
        kept_kind: string
        kept_origin: string
        dropped_kind: string
        dropped_origin: string
        detected_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        day?: string
        kept_kind?: string
        kept_origin?: string
        dropped_kind?: string
        dropped_origin?: string
        detected_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "absence_conflict_log_employee_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    account_tag_mappings: {
      Row: {
        id: string
        tenant_id: string
        tag_id: string
        entity_type: string
        entity_id: string
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        tag_id: string
        entity_type: string
        entity_id: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        tag_id?: string
        entity_type?: string
        entity_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "account_tag_mappings_tag_id_fkey",
          columns: ["tenant_id", "tag_id"],
          isOneToOne: false,
          referencedRelation: "account_tags",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "account_tag_mappings_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    account_tags: {
      Row: {
        id: string
        tenant_id: string
        name: string
        applicability: string
        color: string | null
        country_code: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        applicability?: string
        color?: string
        country_code?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        applicability?: string
        color?: string
        country_code?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "account_tags_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    accounting_control_runs: {
      Row: {
        id: string
        tenant_id: string
        control_type: string
        fiscal_year_id: string | null
        period_id: string | null
        run_date: string
        status: string
        total_checks: number
        errors_found: number
        warnings_found: number
        details: Json
        created_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        control_type: string
        fiscal_year_id?: string
        period_id?: string
        run_date?: string
        status?: string
        total_checks?: number
        errors_found?: number
        warnings_found?: number
        details?: Json
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        control_type?: string
        fiscal_year_id?: string
        period_id?: string
        run_date?: string
        status?: string
        total_checks?: number
        errors_found?: number
        warnings_found?: number
        details?: Json
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "accounting_control_runs_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "acr_fiscal_year_id_fkey",
          columns: ["tenant_id", "fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "acr_period_id_fkey",
          columns: ["tenant_id", "period_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_periods",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    analytic_distribution_lines: {
      Row: {
        id: string
        tenant_id: string
        journal_line_id: string | null
        plan_id: string | null
        section_id: string | null
        percentage: number
        amount: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        journal_line_id?: string
        plan_id?: string
        section_id?: string
        percentage: number
        amount?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        journal_line_id?: string
        plan_id?: string
        section_id?: string
        percentage?: number
        amount?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "analytic_distribution_lines_journal_line_id_fkey",
          columns: ["tenant_id", "journal_line_id"],
          isOneToOne: false,
          referencedRelation: "journal_lines",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "analytic_distribution_lines_plan_id_fkey",
          columns: ["tenant_id", "plan_id"],
          isOneToOne: false,
          referencedRelation: "analytic_plans",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "analytic_distribution_lines_section_id_fkey",
          columns: ["tenant_id", "section_id"],
          isOneToOne: false,
          referencedRelation: "analytic_sections",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "analytic_distribution_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    analytic_journal_codes: {
      Row: {
        id: string
        tenant_id: string
        code: string
        name: string
        description: string | null
        type: string | null
        is_active: boolean | null
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        code: string
        name: string
        description?: string
        type?: string
        is_active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        name?: string
        description?: string
        type?: string
        is_active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "analytic_journal_codes_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    analytic_plans: {
      Row: {
        id: string
        tenant_id: string
        code: string
        name: string
        description: string | null
        is_default: boolean
        active: boolean
        created_at: string
        updated_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        code: string
        name: string
        description?: string
        is_default?: boolean
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        name?: string
        description?: string
        is_default?: boolean
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "analytic_plans_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        section_type: string
      }
      Insert: {
        id?: string
        code: string
        name: string
        parent_id?: string
        axis?: string
        level?: number
        active?: boolean
        created_at?: string
        tenant_id: string
        plan_id?: string
        section_type?: string
      }
      Update: {
        id?: string
        code?: string
        name?: string
        parent_id?: string
        axis?: string
        level?: number
        active?: boolean
        created_at?: string
        tenant_id?: string
        plan_id?: string
        section_type?: string
      }
      Relationships: [
        {
          foreignKeyName: "analytic_sections_parent_id_fkey",
          columns: ["tenant_id", "parent_id"],
          isOneToOne: false,
          referencedRelation: "analytic_sections",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "analytic_sections_plan_id_fkey",
          columns: ["tenant_id", "plan_id"],
          isOneToOne: false,
          referencedRelation: "analytic_plans",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "analytic_sections_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    api_call_logs: {
      Row: {
        id: string
        api_key_id: string | null
        tenant_id: string
        method: string
        path: string
        status: number
        idempotency_key: string | null
        ip_address: string | null
        user_agent: string | null
        duration_ms: number | null
        called_at: string
      }
      Insert: {
        id?: string
        api_key_id?: string
        tenant_id: string
        method: string
        path: string
        status: number
        idempotency_key?: string
        ip_address?: string
        user_agent?: string
        duration_ms?: number
        called_at?: string
      }
      Update: {
        id?: string
        api_key_id?: string
        tenant_id?: string
        method?: string
        path?: string
        status?: number
        idempotency_key?: string
        ip_address?: string
        user_agent?: string
        duration_ms?: number
        called_at?: string
      }
      Relationships: [
      ]
    }
    api_keys: {
      Row: {
        id: string
        tenant_id: string
        name: string
        key_hash: string
        key_prefix: string | null
        permissions: Json | null
        rate_limit_per_min: number | null
        active: boolean | null
        expires_at: string | null
        last_used_at: string | null
        created_by: string | null
        created_at: string
        revoked_at: string | null
        scope: string[] | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        key_hash: string
        key_prefix?: string
        permissions?: Json
        rate_limit_per_min?: number
        active?: boolean
        expires_at?: string
        last_used_at?: string
        created_by?: string
        created_at?: string
        revoked_at?: string
        scope?: string[]
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        key_hash?: string
        key_prefix?: string
        permissions?: Json
        rate_limit_per_min?: number
        active?: boolean
        expires_at?: string
        last_used_at?: string
        created_by?: string
        created_at?: string
        revoked_at?: string
        scope?: string[]
      }
      Relationships: [
      ]
    }
    approval_workflows: {
      Row: {
        id: string
        tenant_id: string
        name: string
        entity_type: string
        steps: Json | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        entity_type: string
        steps?: Json
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        entity_type?: string
        steps?: Json
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "approval_workflows_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    asset_batch_disposal_lines: {
      Row: {
        id: string
        tenant_id: string
        batch_id: string
        asset_id: string
        disposal_type: string | null
        proceeds: number | null
        net_book_value: number | null
        gain_loss: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        batch_id: string
        asset_id: string
        disposal_type?: string
        proceeds?: number
        net_book_value?: number
        gain_loss?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        batch_id?: string
        asset_id?: string
        disposal_type?: string
        proceeds?: number
        net_book_value?: number
        gain_loss?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "asset_batch_disposal_lines_asset_id_fkey",
          columns: ["tenant_id", "asset_id"],
          isOneToOne: false,
          referencedRelation: "fixed_assets",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "asset_batch_disposal_lines_batch_id_fkey",
          columns: ["tenant_id", "batch_id"],
          isOneToOne: false,
          referencedRelation: "asset_batch_disposals",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    asset_batch_disposals: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        batch_number: string
        disposal_date?: string
        total_assets?: number
        total_proceeds?: number
        total_gain_loss?: number
        status?: string
        journal_entry_id?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        batch_number?: string
        disposal_date?: string
        total_assets?: number
        total_proceeds?: number
        total_gain_loss?: number
        status?: string
        journal_entry_id?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
      ]
    }
    asset_depreciation_plans: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        asset_id: string
        plan_type: string
        depreciation_method?: string
        duration_months: number
        residual_value?: number
        annual_rate?: number
        start_date: string
        end_date?: string
        accumulated_depreciation?: number
        current_net_value?: number
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        asset_id?: string
        plan_type?: string
        depreciation_method?: string
        duration_months?: number
        residual_value?: number
        annual_rate?: number
        start_date?: string
        end_date?: string
        accumulated_depreciation?: number
        current_net_value?: number
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "asset_depreciation_plans_asset_id_fkey",
          columns: ["tenant_id", "asset_id"],
          isOneToOne: false,
          referencedRelation: "fixed_assets",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
      Insert: {
        id?: string
        asset_id: string
        fiscal_year_code?: string
        period: number
        depreciation_type: string
        amount?: number
        cumulative_amount?: number
        net_book_value?: number
        entry_number?: string
        created_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        asset_id?: string
        fiscal_year_code?: string
        period?: number
        depreciation_type?: string
        amount?: number
        cumulative_amount?: number
        net_book_value?: number
        entry_number?: string
        created_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "asset_depreciations_asset_id_fkey",
          columns: ["tenant_id", "asset_id"],
          isOneToOne: false,
          referencedRelation: "fixed_assets",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "asset_depreciations_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    asset_documents: {
      Row: {
        id: string
        tenant_id: string
        asset_id: string
        document_type: string | null
        file_url: string
        file_name: string | null
        description: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        asset_id: string
        document_type?: string
        file_url: string
        file_name?: string
        description?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        asset_id?: string
        document_type?: string
        file_url?: string
        file_name?: string
        description?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "asset_documents_asset_id_fkey",
          columns: ["tenant_id", "asset_id"],
          isOneToOne: false,
          referencedRelation: "fixed_assets",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    asset_families: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        code: string
        name: string
        parent_id?: string
        default_account?: string
        default_depreciation_account?: string
        default_duration_months?: number
        default_method?: string
        depreciation_rate?: number
        description?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        name?: string
        parent_id?: string
        default_account?: string
        default_depreciation_account?: string
        default_duration_months?: number
        default_method?: string
        depreciation_rate?: number
        description?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "asset_families_parent_id_fkey",
          columns: ["tenant_id", "parent_id"],
          isOneToOne: false,
          referencedRelation: "asset_families",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    asset_free_fields: {
      Row: {
        id: string
        tenant_id: string
        asset_id: string
        field_key: string
        field_value: string | null
        field_type: string | null
        field_category: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        asset_id: string
        field_key: string
        field_value?: string
        field_type?: string
        field_category?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        asset_id?: string
        field_key?: string
        field_value?: string
        field_type?: string
        field_category?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "asset_free_fields_asset_id_fkey",
          columns: ["tenant_id", "asset_id"],
          isOneToOne: false,
          referencedRelation: "fixed_assets",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    asset_revaluations: {
      Row: {
        id: string
        tenant_id: string
        asset_id: string
        revaluation_date: string
        old_value: number
        new_value: number
        difference: number | null
        reason: string | null
        journal_entry_id: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        asset_id: string
        revaluation_date: string
        old_value?: number
        new_value?: number
        difference?: number
        reason?: string
        journal_entry_id?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        asset_id?: string
        revaluation_date?: string
        old_value?: number
        new_value?: number
        difference?: number
        reason?: string
        journal_entry_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "asset_revaluations_asset_id_fkey",
          columns: ["tenant_id", "asset_id"],
          isOneToOne: false,
          referencedRelation: "fixed_assets",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    asset_split_components: {
      Row: {
        id: string
        tenant_id: string
        split_id: string
        new_asset_id: string
        allocated_value: number
        allocated_percentage: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        split_id: string
        new_asset_id: string
        allocated_value?: number
        allocated_percentage?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        split_id?: string
        new_asset_id?: string
        allocated_value?: number
        allocated_percentage?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "asset_split_components_new_asset_id_fkey",
          columns: ["tenant_id", "new_asset_id"],
          isOneToOne: false,
          referencedRelation: "fixed_assets",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "asset_split_components_split_id_fkey",
          columns: ["tenant_id", "split_id"],
          isOneToOne: false,
          referencedRelation: "asset_splits",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    asset_splits: {
      Row: {
        id: string
        tenant_id: string
        original_asset_id: string
        split_date: string
        reason: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        original_asset_id: string
        split_date?: string
        reason?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        original_asset_id?: string
        split_date?: string
        reason?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "asset_splits_original_asset_id_fkey",
          columns: ["tenant_id", "original_asset_id"],
          isOneToOne: false,
          referencedRelation: "fixed_assets",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    at_rates: {
      Row: {
        id: string
        tenant_id: string
        employee_id: string
        rate: number
        bonus_malus_rate: number | null
        effective_date: string
        expiry_date: string | null
        risk_category: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        rate?: number
        bonus_malus_rate?: number
        effective_date: string
        expiry_date?: string
        risk_category?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        rate?: number
        bonus_malus_rate?: number
        effective_date?: string
        expiry_date?: string
        risk_category?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "at_rates_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "at_rates_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        metadata: Json | null
        ip_address: string | null
        created_at: string | null
        tenant_id: string
      }
      Insert: {
        id?: string
        user_id?: string
        action: string
        entity_type: string
        entity_id?: string
        entity_number?: string
        description?: string
        metadata?: Json
        ip_address?: string
        created_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        user_id?: string
        action?: string
        entity_type?: string
        entity_id?: string
        entity_number?: string
        description?: string
        metadata?: Json
        ip_address?: string
        created_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "audit_log_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "audit_log_user_id_fkey",
          columns: ["tenant_id", "user_id"],
          isOneToOne: false,
          referencedRelation: "users",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    auto_label_rules: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        name: string
        description?: string
        journal_code?: string
        account_code?: string
        account_prefix?: string
        label_pattern: string
        priority?: number
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        description?: string
        journal_code?: string
        account_code?: string
        account_prefix?: string
        label_pattern?: string
        priority?: number
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "auto_label_rules_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        account_code: string | null
        journal_code: string | null
      }
      Insert: {
        id?: string
        name: string
        type: string
        account_number?: string
        sort_code?: string
        balance?: number
        currency?: string
        bank_name?: string
        last_reconciled?: string
        connected?: boolean
        created_at?: string
        updated_at?: string
        tenant_id: string
        statement_balance?: number
        statement_balance_date?: string
        calculated_balance?: number
        reconciliation_diff?: number
        account_code?: string
        journal_code?: string
      }
      Update: {
        id?: string
        name?: string
        type?: string
        account_number?: string
        sort_code?: string
        balance?: number
        currency?: string
        bank_name?: string
        last_reconciled?: string
        connected?: boolean
        created_at?: string
        updated_at?: string
        tenant_id?: string
        statement_balance?: number
        statement_balance_date?: string
        calculated_balance?: number
        reconciliation_diff?: number
        account_code?: string
        journal_code?: string
      }
      Relationships: [
        {
          foreignKeyName: "bank_accounts_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    bank_connections: {
      Row: {
        id: string
        tenant_id: string
        provider: string
        provider_connection_id: string | null
        bank_account_id: string | null
        status: string | null
        last_sync_at: string | null
        sync_frequency: string | null
        next_sync_at: string | null
        error_message: string | null
        metadata: Json | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        provider: string
        provider_connection_id?: string
        bank_account_id?: string
        status?: string
        last_sync_at?: string
        sync_frequency?: string
        next_sync_at?: string
        error_message?: string
        metadata?: Json
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        provider?: string
        provider_connection_id?: string
        bank_account_id?: string
        status?: string
        last_sync_at?: string
        sync_frequency?: string
        next_sync_at?: string
        error_message?: string
        metadata?: Json
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "bank_connections_bank_account_id_fkey",
          columns: ["tenant_id", "bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "bank_connections_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    bank_reconciliation_rules: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        name: string
        afb_code: string
        description?: string
        match_pattern?: string
        counterpart_account?: string
        journal_code?: string
        priority?: number
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        afb_code?: string
        description?: string
        match_pattern?: string
        counterpart_account?: string
        journal_code?: string
        priority?: number
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "bank_reconciliation_rules_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    bank_reconciliation_suggestions: {
      Row: {
        id: string
        tenant_id: string
        bank_transaction_id: string
        invoice_id: string | null
        customer_id: string | null
        supplier_id: string | null
        score: number
        match_type: string
        matched_amount: number | null
        status: string
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        bank_transaction_id: string
        invoice_id?: string
        customer_id?: string
        supplier_id?: string
        score?: number
        match_type?: string
        matched_amount?: number
        status?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        bank_transaction_id?: string
        invoice_id?: string
        customer_id?: string
        supplier_id?: string
        score?: number
        match_type?: string
        matched_amount?: number
        status?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
      ]
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
      Insert: {
        id?: string
        name: string
        condition_field: string
        condition_operator: string
        condition_value: string
        action_category: string
        action_account_code?: string
        action_vat_rate?: number
        priority?: number
        active?: boolean
        created_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        name?: string
        condition_field?: string
        condition_operator?: string
        condition_value?: string
        action_category?: string
        action_account_code?: string
        action_vat_rate?: number
        priority?: number
        active?: boolean
        created_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "bank_rules_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    bank_statement_imports: {
      Row: {
        id: string
        tenant_id: string
        bank_account_id: string | null
        filename: string
        format: string
        file_size: number | null
        status: string
        imported_count: number | null
        error_message: string | null
        imported_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        bank_account_id?: string
        filename: string
        format: string
        file_size?: number
        status?: string
        imported_count?: number
        error_message?: string
        imported_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        bank_account_id?: string
        filename?: string
        format?: string
        file_size?: number
        status?: string
        imported_count?: number
        error_message?: string
        imported_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "bank_statement_imports_bank_account_id_fkey",
          columns: ["tenant_id", "bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "bank_statement_imports_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    bank_statement_templates: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        bank_name: string
        account_number_pattern?: string
        date_pattern: string
        amount_pattern: string
        description_pattern?: string
        reference_pattern?: string
        debit_indicator?: string
        credit_indicator?: string
        period_pattern?: string
        balance_pattern?: string
        currency_pattern?: string
        skip_lines_pattern?: string
        sample_text?: string
        is_active?: boolean
        created_at?: string
        updated_at?: string
        bank_id?: string
        validation_status?: string
        consecutive_successes?: number
        validation_count?: number
        last_validated_at?: string
        last_correction_notes?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        bank_name?: string
        account_number_pattern?: string
        date_pattern?: string
        amount_pattern?: string
        description_pattern?: string
        reference_pattern?: string
        debit_indicator?: string
        credit_indicator?: string
        period_pattern?: string
        balance_pattern?: string
        currency_pattern?: string
        skip_lines_pattern?: string
        sample_text?: string
        is_active?: boolean
        created_at?: string
        updated_at?: string
        bank_id?: string
        validation_status?: string
        consecutive_successes?: number
        validation_count?: number
        last_validated_at?: string
        last_correction_notes?: string
      }
      Relationships: [
        {
          foreignKeyName: "bank_statement_templates_bank_id_fkey",
          columns: ["bank_id"],
          isOneToOne: false,
          referencedRelation: "banks",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "bank_statement_templates_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        label: string | null
        matched_invoice_id: string | null
        matched_account_code: string | null
        match_type: string | null
        bank_account_id: string | null
        kind: string
        matched_line_id: string | null
        provider_transaction_id: string | null
      }
      Insert: {
        id?: string
        account_id?: string
        date?: string
        description: string
        reference?: string
        type: string
        amount?: number
        category?: string
        reconciled?: boolean
        matched?: boolean
        invoice_id?: string
        purchase_invoice_id?: string
        created_at?: string
        tenant_id: string
        afb_code?: string
        reconciled_entry_id?: string
        reconciled_at?: string
        original_currency?: string
        original_amount?: number
        exchange_rate?: number
        exchange_gain_loss?: number
        source?: string
        label?: string
        matched_invoice_id?: string
        matched_account_code?: string
        match_type?: string
        bank_account_id?: string
        kind?: string
        matched_line_id?: string
        provider_transaction_id?: string
      }
      Update: {
        id?: string
        account_id?: string
        date?: string
        description?: string
        reference?: string
        type?: string
        amount?: number
        category?: string
        reconciled?: boolean
        matched?: boolean
        invoice_id?: string
        purchase_invoice_id?: string
        created_at?: string
        tenant_id?: string
        afb_code?: string
        reconciled_entry_id?: string
        reconciled_at?: string
        original_currency?: string
        original_amount?: number
        exchange_rate?: number
        exchange_gain_loss?: number
        source?: string
        label?: string
        matched_invoice_id?: string
        matched_account_code?: string
        match_type?: string
        bank_account_id?: string
        kind?: string
        matched_line_id?: string
        provider_transaction_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "bank_transactions_account_id_fkey",
          columns: ["tenant_id", "account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "bank_transactions_invoice_id_fkey",
          columns: ["tenant_id", "invoice_id"],
          isOneToOne: false,
          referencedRelation: "invoices",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "bank_transactions_matched_line_id_fkey",
          columns: ["tenant_id", "matched_line_id"],
          isOneToOne: false,
          referencedRelation: "journal_lines",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "bank_transactions_purchase_invoice_id_fkey",
          columns: ["tenant_id", "purchase_invoice_id"],
          isOneToOne: false,
          referencedRelation: "purchase_invoices",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "bank_transactions_reconciled_entry_id_fkey",
          columns: ["tenant_id", "reconciled_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "bank_transactions_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        name: string
        swift_code?: string
        country?: string
        logo_url?: string
        is_active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        name?: string
        swift_code?: string
        country?: string
        logo_url?: string
        is_active?: boolean
        created_at?: string
      }
      Relationships: [
      ]
    }
    batch_entry_sessions: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        session_name: string
        journal_code: string
        session_date: string
        entry_count?: number
        total_debit?: number
        total_credit?: number
        status?: string
        validated_at?: string
        validated_by?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        session_name?: string
        journal_code?: string
        session_date?: string
        entry_count?: number
        total_debit?: number
        total_credit?: number
        status?: string
        validated_at?: string
        validated_by?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "batch_entry_sessions_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    bdes_indicators: {
      Row: {
        id: string
        tenant_id: string
        year: number
        category: string
        indicator_name: string
        indicator_value: number | null
        indicator_unit: string | null
        breakdown: Json | null
        target_value: number | null
        previous_year_value: number | null
        notes: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        year: number
        category: string
        indicator_name: string
        indicator_value?: number
        indicator_unit?: string
        breakdown?: Json
        target_value?: number
        previous_year_value?: number
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        year?: number
        category?: string
        indicator_name?: string
        indicator_value?: number
        indicator_unit?: string
        breakdown?: Json
        target_value?: number
        previous_year_value?: number
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "bdes_indicators_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        scrap_rate: number | null
        lot_id: string | null
      }
      Insert: {
        id?: string
        bom_id?: string
        product_id: string
        quantity?: number
        unit_cost?: number
        position?: number
        tenant_id: string
        scrap_rate?: number
        lot_id?: string
      }
      Update: {
        id?: string
        bom_id?: string
        product_id?: string
        quantity?: number
        unit_cost?: number
        position?: number
        tenant_id?: string
        scrap_rate?: number
        lot_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "bom_lines_bom_id_fkey",
          columns: ["tenant_id", "bom_id"],
          isOneToOne: false,
          referencedRelation: "boms",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "bom_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "bom_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        code: string
        name: string
        product_id?: string
        quantity?: number
        unit?: string
        active?: boolean
        created_at?: string
        tenant_id: string
        routing_id?: string
        bom_type?: string
      }
      Update: {
        id?: string
        code?: string
        name?: string
        product_id?: string
        quantity?: number
        unit?: string
        active?: boolean
        created_at?: string
        tenant_id?: string
        routing_id?: string
        bom_type?: string
      }
      Relationships: [
        {
          foreignKeyName: "boms_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "boms_routing_id_fkey",
          columns: ["tenant_id", "routing_id"],
          isOneToOne: false,
          referencedRelation: "routings",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "boms_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        description: string
        account_code: string
        fiscal_year_id?: string
        amount?: number
        commitment_date?: string
        source_type?: string
        source_id?: string
        status?: string
        supplier_id?: string
        notes?: string
        created_at?: string
        updated_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        description?: string
        account_code?: string
        fiscal_year_id?: string
        amount?: number
        commitment_date?: string
        source_type?: string
        source_id?: string
        status?: string
        supplier_id?: string
        notes?: string
        created_at?: string
        updated_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "budget_commitments_fiscal_year_id_fkey",
          columns: ["tenant_id", "fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "budget_commitments_supplier_id_fkey",
          columns: ["tenant_id", "supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "budget_commitments_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        name: string
        fiscal_year_id?: string
        account_code?: string
        analytic_section_id?: string
        period_1?: number
        period_2?: number
        period_3?: number
        period_4?: number
        period_5?: number
        period_6?: number
        period_7?: number
        period_8?: number
        period_9?: number
        period_10?: number
        period_11?: number
        period_12?: number
        created_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        name?: string
        fiscal_year_id?: string
        account_code?: string
        analytic_section_id?: string
        period_1?: number
        period_2?: number
        period_3?: number
        period_4?: number
        period_5?: number
        period_6?: number
        period_7?: number
        period_8?: number
        period_9?: number
        period_10?: number
        period_11?: number
        period_12?: number
        created_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "budgets_analytic_section_id_fkey",
          columns: ["tenant_id", "analytic_section_id"],
          isOneToOne: false,
          referencedRelation: "analytic_sections",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "budgets_fiscal_year_id_fkey",
          columns: ["tenant_id", "fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "budgets_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    career_history: {
      Row: {
        id: string
        tenant_id: string
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
        documents: Json | null
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        position?: string
        department?: string
        salary?: number
        start_date: string
        end_date?: string
        change_type?: string
        notes?: string
        created_at?: string
        event_type?: string
        event_date?: string
        previous_position?: string
        new_position?: string
        previous_department?: string
        new_department?: string
        previous_salary?: number
        new_salary?: number
        previous_manager_id?: string
        new_manager_id?: string
        previous_collective_agreement_id?: string
        new_collective_agreement_id?: string
        reason?: string
        documents?: Json
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        position?: string
        department?: string
        salary?: number
        start_date?: string
        end_date?: string
        change_type?: string
        notes?: string
        created_at?: string
        event_type?: string
        event_date?: string
        previous_position?: string
        new_position?: string
        previous_department?: string
        new_department?: string
        previous_salary?: number
        new_salary?: number
        previous_manager_id?: string
        new_manager_id?: string
        previous_collective_agreement_id?: string
        new_collective_agreement_id?: string
        reason?: string
        documents?: Json
      }
      Relationships: [
        {
          foreignKeyName: "career_history_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    carry_forward_log: {
      Row: {
        id: string
        tenant_id: string
        source_fiscal_year_id: string
        target_fiscal_year_id: string | null
        carry_forward_date: string
        total_debit: number
        total_credit: number
        entry_count: number
        status: string
        journal_entry_id: string | null
        created_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        source_fiscal_year_id: string
        target_fiscal_year_id?: string
        carry_forward_date: string
        total_debit?: number
        total_credit?: number
        entry_count?: number
        status?: string
        journal_entry_id?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        source_fiscal_year_id?: string
        target_fiscal_year_id?: string
        carry_forward_date?: string
        total_debit?: number
        total_credit?: number
        entry_count?: number
        status?: string
        journal_entry_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "carry_forward_log_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "cfl_journal_entry_id_fkey",
          columns: ["tenant_id", "journal_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "cfl_source_fy_fkey",
          columns: ["tenant_id", "source_fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "cfl_target_fy_fkey",
          columns: ["tenant_id", "target_fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    cash_control_sessions: {
      Row: {
        id: string
        tenant_id: string
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
        details: Json
        created_at: string
        updated_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        session_number: string
        journal_code: string
        session_date: string
        theoretical_balance?: number
        counted_balance?: number
        difference?: number
        status?: string
        counted_by?: string
        validated_by?: string
        validated_at?: string
        notes?: string
        details?: Json
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        session_number?: string
        journal_code?: string
        session_date?: string
        theoretical_balance?: number
        counted_balance?: number
        difference?: number
        status?: string
        counted_by?: string
        validated_by?: string
        validated_at?: string
        notes?: string
        details?: Json
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "cash_control_sessions_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    chain_banc_maillons: {
      Row: {
        code: string
        libelle: string
        effet: string
        document_type: string
        evenement: string
        amont_type: string
        fonction: string
        arguments: Json
        sens: string
        actif: boolean
        note: string | null
        created_at: string
        appat: string | null
        arg_valeurs: Json
        arg_types: string[] | null
        defaut_dblink: boolean
        budget_ms: number
        appat_annul: string | null
        appat_reouverture: string | null
        arg_series: Json
        arg_valeurs_annul: Json | null
        arg_types_annul: string[] | null
        arg_valeurs_reouverture: Json | null
        arg_types_reouverture: string[] | null
        nature: string
      }
      Insert: {
        code: string
        libelle: string
        effet: string
        document_type: string
        evenement: string
        amont_type: string
        fonction: string
        arguments?: Json
        sens?: string
        actif?: boolean
        note?: string
        created_at?: string
        appat?: string
        arg_valeurs?: Json
        arg_types?: string[]
        defaut_dblink?: boolean
        budget_ms?: number
        appat_annul?: string
        appat_reouverture?: string
        arg_series?: Json
        arg_valeurs_annul?: Json
        arg_types_annul?: string[]
        arg_valeurs_reouverture?: Json
        arg_types_reouverture?: string[]
        nature?: string
      }
      Update: {
        code?: string
        libelle?: string
        effet?: string
        document_type?: string
        evenement?: string
        amont_type?: string
        fonction?: string
        arguments?: Json
        sens?: string
        actif?: boolean
        note?: string
        created_at?: string
        appat?: string
        arg_valeurs?: Json
        arg_types?: string[]
        defaut_dblink?: boolean
        budget_ms?: number
        appat_annul?: string
        appat_reouverture?: string
        arg_series?: Json
        arg_valeurs_annul?: Json
        arg_types_annul?: string[]
        arg_valeurs_reouverture?: Json
        arg_types_reouverture?: string[]
        nature?: string
      }
      Relationships: [
      ]
    }
    chain_banc_resultats: {
      Row: {
        id: number
        code: string
        epreuve: string
        tenant_id: string
        joue_le: string
        verdict: string
        mesure: number | null
        attendu: string | null
        obtenu: string | null
        duree_ms: number | null
        raison: string | null
      }
      Insert: {
        id?: number
        code: string
        epreuve: string
        tenant_id: string
        joue_le?: string
        verdict: string
        mesure?: number
        attendu?: string
        obtenu?: string
        duree_ms?: number
        raison?: string
      }
      Update: {
        id?: number
        code?: string
        epreuve?: string
        tenant_id?: string
        joue_le?: string
        verdict?: string
        mesure?: number
        attendu?: string
        obtenu?: string
        duree_ms?: number
        raison?: string
      }
      Relationships: [
        {
          foreignKeyName: "chain_banc_resultats_code_fkey",
          columns: ["code"],
          isOneToOne: true,
          referencedRelation: "chain_banc_maillons",
          referencedColumns: ["code"]
        },
        {
          foreignKeyName: "chain_banc_resultats_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    chain_document_types: {
      Row: {
        code: string
        table_name: string
        ligne_table: string | null
        libelle_fr: string
        created_at: string
      }
      Insert: {
        code: string
        table_name: string
        ligne_table?: string
        libelle_fr: string
        created_at?: string
      }
      Update: {
        code?: string
        table_name?: string
        ligne_table?: string
        libelle_fr?: string
        created_at?: string
      }
      Relationships: [
      ]
    }
    chain_invariant_alertes: {
      Row: {
        id: number
        tenant_id: string
        code: string
        mesure_le: string
        verdict_avant: string
        verdict_apres: string
        mesure_avant: number | null
        mesure_apres: number | null
        lignes_avant: number
        lignes_apres: number
        delta: number | null
        motif: string
        notifiee: boolean
        created_at: string
        releve_id: number | null
        releve_avant_id: number | null
      }
      Insert: {
        id?: number
        tenant_id: string
        code: string
        mesure_le: string
        verdict_avant: string
        verdict_apres: string
        mesure_avant?: number
        mesure_apres?: number
        lignes_avant?: number
        lignes_apres?: number
        delta?: number
        motif: string
        notifiee?: boolean
        created_at?: string
        releve_id?: number
        releve_avant_id?: number
      }
      Update: {
        id?: number
        tenant_id?: string
        code?: string
        mesure_le?: string
        verdict_avant?: string
        verdict_apres?: string
        mesure_avant?: number
        mesure_apres?: number
        lignes_avant?: number
        lignes_apres?: number
        delta?: number
        motif?: string
        notifiee?: boolean
        created_at?: string
        releve_id?: number
        releve_avant_id?: number
      }
      Relationships: [
        {
          foreignKeyName: "chain_invariant_alertes_releve_avant_fkey",
          columns: ["tenant_id", "releve_avant_id"],
          isOneToOne: false,
          referencedRelation: "chain_invariant_results",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "chain_invariant_alertes_releve_fkey",
          columns: ["tenant_id", "releve_id"],
          isOneToOne: false,
          referencedRelation: "chain_invariant_results",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "chain_invariant_alertes_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    chain_invariant_results: {
      Row: {
        id: number
        tenant_id: string
        code: string
        verdict: string
        mesure_a: number | null
        mesure_b: number | null
        ecart: number | null
        lignes_en_ecart: number
        duree_ms: number
        detail: Json | null
        mesure_le: string
      }
      Insert: {
        id?: number
        tenant_id: string
        code: string
        verdict: string
        mesure_a?: number
        mesure_b?: number
        ecart?: number
        lignes_en_ecart?: number
        duree_ms?: number
        detail?: Json
        mesure_le?: string
      }
      Update: {
        id?: number
        tenant_id?: string
        code?: string
        verdict?: string
        mesure_a?: number
        mesure_b?: number
        ecart?: number
        lignes_en_ecart?: number
        duree_ms?: number
        detail?: Json
        mesure_le?: string
      }
      Relationships: [
        {
          foreignKeyName: "chain_invariant_results_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    chain_invariants: {
      Row: {
        id: string
        tenant_id: string | null
        code: string
        libelle: string
        modules: string[]
        source_a: string
        source_b: string
        sens: string
        tolerance: number
        mesurable: boolean
        raison_non_mesurable: string | null
        actif: boolean
        note: string | null
        created_at: string
      }
      Insert: {
        id?: string
        tenant_id?: string
        code: string
        libelle: string
        modules?: string[]
        source_a: string
        source_b: string
        sens?: string
        tolerance?: number
        mesurable?: boolean
        raison_non_mesurable?: string
        actif?: boolean
        note?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        libelle?: string
        modules?: string[]
        source_a?: string
        source_b?: string
        sens?: string
        tolerance?: number
        mesurable?: boolean
        raison_non_mesurable?: string
        actif?: boolean
        note?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "chain_invariants_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: false,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    chain_regeneration_log: {
      Row: {
        id: number
        tenant_id: string
        effet: string
        amont_type: string
        amont_id: string
        cause: string
        avant: Json | null
        apres: Json | null
        created_by: string | null
        created_at: string
      }
      Insert: {
        id?: number
        tenant_id: string
        effet: string
        amont_type: string
        amont_id: string
        cause: string
        avant?: Json
        apres?: Json
        created_by?: string
        created_at?: string
      }
      Update: {
        id?: number
        tenant_id?: string
        effet?: string
        amont_type?: string
        amont_id?: string
        cause?: string
        avant?: Json
        apres?: Json
        created_by?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "chain_regeneration_log_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    chain_settings: {
      Row: {
        tenant_id: string
        enforcement: string
        updated_at: string
        updated_by: string | null
      }
      Insert: {
        tenant_id: string
        enforcement?: string
        updated_at?: string
        updated_by?: string
      }
      Update: {
        tenant_id?: string
        enforcement?: string
        updated_at?: string
        updated_by?: string
      }
      Relationships: [
        {
          foreignKeyName: "chain_settings_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    chain_traces: {
      Row: {
        id: number
        tenant_id: string
        effet: string
        amont_type: string
        amont_id: string
        amont_ligne_id: string | null
        duree_ms: number
        lignes_ecrites: number
        verrous_attendus_ms: number | null
        resultat: string
        message: string | null
        created_at: string
      }
      Insert: {
        id?: number
        tenant_id: string
        effet: string
        amont_type: string
        amont_id: string
        amont_ligne_id?: string
        duree_ms?: number
        lignes_ecrites?: number
        verrous_attendus_ms?: number
        resultat: string
        message?: string
        created_at?: string
      }
      Update: {
        id?: number
        tenant_id?: string
        effet?: string
        amont_type?: string
        amont_id?: string
        amont_ligne_id?: string
        duree_ms?: number
        lignes_ecrites?: number
        verrous_attendus_ms?: number
        resultat?: string
        message?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "chain_traces_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        pack_code: string
        code: string
        name: string
        type: string
        vat_rate?: string
        parent_code?: string
        sort_order?: number
        created_at?: string
      }
      Update: {
        id?: string
        pack_code?: string
        code?: string
        name?: string
        type?: string
        vat_rate?: string
        parent_code?: string
        sort_order?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "chart_account_templates_pack_code_fkey",
          columns: ["pack_code"],
          isOneToOne: true,
          referencedRelation: "legislation_packs",
          referencedColumns: ["code"]
        },
      ]
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
      Insert: {
        id?: string
        code: string
        name: string
        type: string
        balance?: number
        vat_rate?: string
        description?: string
        parent_id?: string
        created_at?: string
        tenant_id: string
        racine?: string
        classe?: string
        nature?: string
        code_taxe_default?: string
        saisie_analytic?: boolean
        saisie_echeance?: boolean
        saisie_tiers?: boolean
        debit_n1?: number
        credit_n1?: number
        current_debit?: number
        current_credit?: number
        current_balance?: number
        currency_code?: string
        reconcile?: boolean
        deprecated?: boolean
        account_type?: string
      }
      Update: {
        id?: string
        code?: string
        name?: string
        type?: string
        balance?: number
        vat_rate?: string
        description?: string
        parent_id?: string
        created_at?: string
        tenant_id?: string
        racine?: string
        classe?: string
        nature?: string
        code_taxe_default?: string
        saisie_analytic?: boolean
        saisie_echeance?: boolean
        saisie_tiers?: boolean
        debit_n1?: number
        credit_n1?: number
        current_debit?: number
        current_credit?: number
        current_balance?: number
        currency_code?: string
        reconcile?: boolean
        deprecated?: boolean
        account_type?: string
      }
      Relationships: [
        {
          foreignKeyName: "chart_accounts_parent_id_fkey",
          columns: ["tenant_id", "parent_id"],
          isOneToOne: false,
          referencedRelation: "chart_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "chart_accounts_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    chart_pack_status: {
      Row: {
        pack_code: string
        status: string
        account_count: number
        uploaded_by: string | null
        uploaded_at: string | null
        published_by: string | null
        published_at: string | null
        source: string
      }
      Insert: {
        pack_code: string
        status?: string
        account_count?: number
        uploaded_by?: string
        uploaded_at?: string
        published_by?: string
        published_at?: string
        source?: string
      }
      Update: {
        pack_code?: string
        status?: string
        account_count?: number
        uploaded_by?: string
        uploaded_at?: string
        published_by?: string
        published_at?: string
        source?: string
      }
      Relationships: [
        {
          foreignKeyName: "chart_pack_status_pack_code_fkey",
          columns: ["pack_code"],
          isOneToOne: true,
          referencedRelation: "legislation_packs",
          referencedColumns: ["code"]
        },
      ]
    }
    chart_pack_switch_log: {
      Row: {
        id: string
        tenant_id: string
        from_pack: string | null
        to_pack: string
        switched: boolean
        detail: Json
        created_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        from_pack?: string
        to_pack: string
        switched: boolean
        detail?: Json
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        from_pack?: string
        to_pack?: string
        switched?: boolean
        detail?: Json
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "chart_pack_switch_log_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    chart_provisional_fallbacks: {
      Row: {
        country_code: string
        fallback_pack: string
      }
      Insert: {
        country_code: string
        fallback_pack: string
      }
      Update: {
        country_code?: string
        fallback_pack?: string
      }
      Relationships: [
        {
          foreignKeyName: "chart_provisional_fallbacks_fallback_pack_fkey",
          columns: ["fallback_pack"],
          isOneToOne: true,
          referencedRelation: "legislation_packs",
          referencedColumns: ["code"]
        },
      ]
    }
    chart_required_accounts: {
      Row: {
        code: string
        source: string
        reason: string
      }
      Insert: {
        code: string
        source: string
        reason: string
      }
      Update: {
        code?: string
        source?: string
        reason?: string
      }
      Relationships: [
      ]
    }
    check_books: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        bank_account_id?: string
        journal_id?: string
        name: string
        first_check_number: string
        last_check_number: string
        next_check_number: string
        status?: string
        issued_count?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        bank_account_id?: string
        journal_id?: string
        name?: string
        first_check_number?: string
        last_check_number?: string
        next_check_number?: string
        status?: string
        issued_count?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "check_books_bank_account_id_fkey",
          columns: ["tenant_id", "bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "check_books_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    checks: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        check_book_id?: string
        check_number: string
        amount: number
        payee: string
        issue_date: string
        due_date?: string
        status?: string
        journal_entry_id?: string
        payment_id?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        check_book_id?: string
        check_number?: string
        amount?: number
        payee?: string
        issue_date?: string
        due_date?: string
        status?: string
        journal_entry_id?: string
        payment_id?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "checks_check_book_id_fkey",
          columns: ["tenant_id", "check_book_id"],
          isOneToOne: false,
          referencedRelation: "check_books",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "checks_journal_entry_id_fkey",
          columns: ["tenant_id", "journal_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "checks_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    cice_config: {
      Row: {
        id: string
        tenant_id: string
        year: number
        smic_threshold: number | null
        rate: number | null
        eligible_salary_cap: number | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        year: number
        smic_threshold?: number
        rate?: number
        eligible_salary_cap?: number
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        year?: number
        smic_threshold?: number
        rate?: number
        eligible_salary_cap?: number
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "cice_config_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        days_overdue: number | null
        sent_at: string | null
        email_sent: boolean | null
        last_error: string | null
      }
      Insert: {
        id?: string
        number: string
        customer_id?: string
        third_party_id?: string
        invoice_id?: string
        reminder_level?: number
        reminder_date?: string
        due_date?: string
        amount?: number
        status?: string
        notes?: string
        created_at?: string
        tenant_id: string
        payment_link_token?: string
        payment_link_url?: string
        payment_link_expires_at?: string
        payment_status?: string
        reminder_level_id?: string
        dispute_id?: string
        promise_id?: string
        days_overdue?: number
        sent_at?: string
        email_sent?: boolean
        last_error?: string
      }
      Update: {
        id?: string
        number?: string
        customer_id?: string
        third_party_id?: string
        invoice_id?: string
        reminder_level?: number
        reminder_date?: string
        due_date?: string
        amount?: number
        status?: string
        notes?: string
        created_at?: string
        tenant_id?: string
        payment_link_token?: string
        payment_link_url?: string
        payment_link_expires_at?: string
        payment_status?: string
        reminder_level_id?: string
        dispute_id?: string
        promise_id?: string
        days_overdue?: number
        sent_at?: string
        email_sent?: boolean
        last_error?: string
      }
      Relationships: [
        {
          foreignKeyName: "collection_reminders_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "collection_reminders_dispute_id_fkey",
          columns: ["tenant_id", "dispute_id"],
          isOneToOne: false,
          referencedRelation: "disputes",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "collection_reminders_invoice_id_fkey",
          columns: ["tenant_id", "invoice_id"],
          isOneToOne: false,
          referencedRelation: "invoices",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "collection_reminders_promise_id_fkey",
          columns: ["tenant_id", "promise_id"],
          isOneToOne: false,
          referencedRelation: "payment_promises",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "collection_reminders_reminder_level_id_fkey",
          columns: ["tenant_id", "reminder_level_id"],
          isOneToOne: false,
          referencedRelation: "reminder_levels",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "collection_reminders_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "collection_reminders_third_party_id_fkey",
          columns: ["tenant_id", "third_party_id"],
          isOneToOne: false,
          referencedRelation: "third_party_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    collective_agreements: {
      Row: {
        id: string
        tenant_id: string
        idcc_code: string
        name: string
        application_date: string
        is_active: boolean | null
        metadata: Json | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        idcc_code: string
        name: string
        application_date?: string
        is_active?: boolean
        metadata?: Json
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        idcc_code?: string
        name?: string
        application_date?: string
        is_active?: boolean
        metadata?: Json
        created_at?: string
      }
      Relationships: [
      ]
    }
    collective_classifications: {
      Row: {
        id: string
        tenant_id: string
        agreement_id: string
        category: string | null
        level: string | null
        echelon: string | null
        coefficient: number
        minimum_monthly_salary: number
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        agreement_id: string
        category?: string
        level?: string
        echelon?: string
        coefficient: number
        minimum_monthly_salary: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        agreement_id?: string
        category?: string
        level?: string
        echelon?: string
        coefficient?: number
        minimum_monthly_salary?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "collective_classifications_agreement_id_fkey",
          columns: ["tenant_id", "agreement_id"],
          isOneToOne: false,
          referencedRelation: "collective_agreements",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    compaction_logs: {
      Row: {
        id: string
        tenant_id: string
        fiscal_year_id: string | null
        entries_compacted: number
        lines_compacted: number
        status: string
        compacted_by: string | null
        compacted_at: string
        details: Json | null
      }
      Insert: {
        id?: string
        tenant_id: string
        fiscal_year_id?: string
        entries_compacted?: number
        lines_compacted?: number
        status?: string
        compacted_by?: string
        compacted_at?: string
        details?: Json
      }
      Update: {
        id?: string
        tenant_id?: string
        fiscal_year_id?: string
        entries_compacted?: number
        lines_compacted?: number
        status?: string
        compacted_by?: string
        compacted_at?: string
        details?: Json
      }
      Relationships: [
        {
          foreignKeyName: "cl_fiscal_year_id_fkey",
          columns: ["tenant_id", "fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "compaction_logs_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        stock_valuation_method: string | null
        overhead_rate: number | null
        absence_method: string | null
        next_lettrage_seq: number | null
        enforce_segregation: boolean | null
        ocr_consent: boolean
        ocr_consent_at: string | null
        ocr_consent_by: string | null
      }
      Insert: {
        id?: string
        name: string
        legal_name?: string
        vat_number?: string
        siret?: string
        address?: string
        city?: string
        postal_code?: string
        country?: string
        currency?: string
        fiscal_year_start?: string
        email?: string
        phone?: string
        website?: string
        logo_url?: string
        created_at?: string
        updated_at?: string
        tenant_id: string
        country_code?: string
        legislation_pack_code?: string
        vat_method?: string
        gdpr_enabled?: boolean
        gdpr_retention_years?: number
        gdpr_anonymize_after?: boolean
        accounting_standard?: string
        saisie_negative?: boolean
        multi_currency?: boolean
        show_quantities?: boolean
        vat_regime?: string
        vat_periodicity?: string
        stock_valuation_method?: string
        overhead_rate?: number
        absence_method?: string
        next_lettrage_seq?: number
        enforce_segregation?: boolean
        ocr_consent?: boolean
        ocr_consent_at?: string
        ocr_consent_by?: string
      }
      Update: {
        id?: string
        name?: string
        legal_name?: string
        vat_number?: string
        siret?: string
        address?: string
        city?: string
        postal_code?: string
        country?: string
        currency?: string
        fiscal_year_start?: string
        email?: string
        phone?: string
        website?: string
        logo_url?: string
        created_at?: string
        updated_at?: string
        tenant_id?: string
        country_code?: string
        legislation_pack_code?: string
        vat_method?: string
        gdpr_enabled?: boolean
        gdpr_retention_years?: number
        gdpr_anonymize_after?: boolean
        accounting_standard?: string
        saisie_negative?: boolean
        multi_currency?: boolean
        show_quantities?: boolean
        vat_regime?: string
        vat_periodicity?: string
        stock_valuation_method?: string
        overhead_rate?: number
        absence_method?: string
        next_lettrage_seq?: number
        enforce_segregation?: boolean
        ocr_consent?: boolean
        ocr_consent_at?: string
        ocr_consent_by?: string
      }
      Relationships: [
        {
          foreignKeyName: "company_settings_legislation_pack_code_fkey",
          columns: ["tenant_id", "legislation_pack_code"],
          isOneToOne: false,
          referencedRelation: "legislation_packs",
          referencedColumns: ["tenant_id", "code"]
        },
        {
          foreignKeyName: "company_settings_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    consolidated_treasury: {
      Row: {
        id: string
        tenant_id: string
        consolidation_date: string
        total_assets: number | null
        total_liabilities: number | null
        net_position: number | null
        details: Json | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        consolidation_date?: string
        total_assets?: number
        total_liabilities?: number
        net_position?: number
        details?: Json
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        consolidation_date?: string
        total_assets?: number
        total_liabilities?: number
        net_position?: number
        details?: Json
        created_at?: string
      }
      Relationships: [
      ]
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
      Insert: {
        id?: string
        number: string
        employee_id: string
        contract_type: string
        start_date: string
        end_date?: string
        position?: string
        department?: string
        monthly_salary?: number
        hourly_rate?: number
        weekly_hours?: number
        trial_period_days?: number
        status?: string
        notes?: string
        created_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        number?: string
        employee_id?: string
        contract_type?: string
        start_date?: string
        end_date?: string
        position?: string
        department?: string
        monthly_salary?: number
        hourly_rate?: number
        weekly_hours?: number
        trial_period_days?: number
        status?: string
        notes?: string
        created_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "contracts_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "contracts_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        grid_id: string
        line_type: string
        label: string
        base_type?: string
        min_amount?: number
        max_amount?: number
        rate?: number
        cap_amount?: number
        fixed_amount?: number
        sort_order?: number
        created_at?: string
      }
      Update: {
        id?: string
        grid_id?: string
        line_type?: string
        label?: string
        base_type?: string
        min_amount?: number
        max_amount?: number
        rate?: number
        cap_amount?: number
        fixed_amount?: number
        sort_order?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "corporate_tax_grid_lines_grid_id_fkey",
          columns: ["grid_id"],
          isOneToOne: true,
          referencedRelation: "corporate_tax_grids",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id?: string
        country_code: string
        tax_type: string
        name: string
        description?: string
        effective_from?: string
        effective_to?: string
        status?: string
        source?: string
        file_url?: string
        is_default?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        country_code?: string
        tax_type?: string
        name?: string
        description?: string
        effective_from?: string
        effective_to?: string
        status?: string
        source?: string
        file_url?: string
        is_default?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "corporate_tax_grids_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: false,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    cpf_accounts: {
      Row: {
        id: string
        tenant_id: string
        employee_id: string
        balance_hours: number | null
        balance_amount: number | null
        history: Json | null
        created_at: string | null
        updated_at: string | null
        last_sync_date: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        balance_hours?: number
        balance_amount?: number
        history?: Json
        created_at?: string
        updated_at?: string
        last_sync_date?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        balance_hours?: number
        balance_amount?: number
        history?: Json
        created_at?: string
        updated_at?: string
        last_sync_date?: string
      }
      Relationships: [
        {
          foreignKeyName: "cpf_accounts_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    cpf_transactions: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        transaction_type: string
        hours?: number
        amount?: number
        training_label?: string
        training_start_date?: string
        training_end_date?: string
        training_provider?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        transaction_type?: string
        hours?: number
        amount?: number
        training_label?: string
        training_start_date?: string
        training_end_date?: string
        training_provider?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "cpf_transactions_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "cpf_transactions_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    credit_lines: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        bank_account_id?: string
        name: string
        type?: string
        limit_amount?: number
        used_amount?: number
        interest_rate?: number
        start_date?: string
        end_date?: string
        monthly_payment?: number
        status?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        bank_account_id?: string
        name?: string
        type?: string
        limit_amount?: number
        used_amount?: number
        interest_rate?: number
        start_date?: string
        end_date?: string
        monthly_payment?: number
        status?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "credit_lines_bank_account_id_fkey",
          columns: ["tenant_id", "bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
        product_id: string | null
        vat_code: string | null
        vat_amount: number
        account_code: string | null
        analytic_section_id: string | null
      }
      Insert: {
        id?: string
        credit_note_id?: string
        description: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        total?: number
        vat_total?: number
        line_order?: number
        created_at?: string
        tenant_id: string
        product_id?: string
        vat_code?: string
        vat_amount?: number
        account_code?: string
        analytic_section_id?: string
      }
      Update: {
        id?: string
        credit_note_id?: string
        description?: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        total?: number
        vat_total?: number
        line_order?: number
        created_at?: string
        tenant_id?: string
        product_id?: string
        vat_code?: string
        vat_amount?: number
        account_code?: string
        analytic_section_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "credit_note_lines_analytic_section_fkey",
          columns: ["tenant_id", "analytic_section_id"],
          isOneToOne: false,
          referencedRelation: "analytic_sections",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "credit_note_lines_credit_note_id_fkey",
          columns: ["tenant_id", "credit_note_id"],
          isOneToOne: false,
          referencedRelation: "credit_notes",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "credit_note_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "credit_note_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        transferred_entry_id: string | null
        validated_at: string | null
      }
      Insert: {
        id?: string
        number: string
        customer_id?: string
        customer_name?: string
        date?: string
        status?: string
        subtotal?: number
        vat_total?: number
        total?: number
        reason?: string
        invoice_id?: string
        created_at?: string
        tenant_id: string
        currency_code?: string
        exchange_rate?: number
        amount_untaxed_currency?: number
        amount_tax_currency?: number
        amount_total_currency?: number
        source_invoice_id?: string
        transferred_entry_id?: string
        validated_at?: string
      }
      Update: {
        id?: string
        number?: string
        customer_id?: string
        customer_name?: string
        date?: string
        status?: string
        subtotal?: number
        vat_total?: number
        total?: number
        reason?: string
        invoice_id?: string
        created_at?: string
        tenant_id?: string
        currency_code?: string
        exchange_rate?: number
        amount_untaxed_currency?: number
        amount_tax_currency?: number
        amount_total_currency?: number
        source_invoice_id?: string
        transferred_entry_id?: string
        validated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "credit_notes_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "credit_notes_invoice_id_fkey",
          columns: ["tenant_id", "invoice_id"],
          isOneToOne: false,
          referencedRelation: "invoices",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "credit_notes_source_invoice_id_fkey",
          columns: ["tenant_id", "source_invoice_id"],
          isOneToOne: false,
          referencedRelation: "invoices",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "credit_notes_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "credit_notes_transferred_entry_id_fkey",
          columns: ["tenant_id", "transferred_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    crm_activities: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        opportunity_id?: string
        customer_id?: string
        activity_type: string
        subject: string
        description?: string
        scheduled_date?: string
        completed_date?: string
        duration_minutes?: number
        status?: string
        assigned_to?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        opportunity_id?: string
        customer_id?: string
        activity_type?: string
        subject?: string
        description?: string
        scheduled_date?: string
        completed_date?: string
        duration_minutes?: number
        status?: string
        assigned_to?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "crm_activities_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "crm_activities_opportunity_id_fkey",
          columns: ["tenant_id", "opportunity_id"],
          isOneToOne: false,
          referencedRelation: "crm_opportunities",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "crm_activities_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    crm_campaign_recipients: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        campaign_id: string
        customer_id?: string
        prospect_id?: string
        email?: string
        phone?: string
        sent?: boolean
        sent_at?: string
        opened?: boolean
        opened_at?: string
        clicked?: boolean
        responded?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        campaign_id?: string
        customer_id?: string
        prospect_id?: string
        email?: string
        phone?: string
        sent?: boolean
        sent_at?: string
        opened?: boolean
        opened_at?: string
        clicked?: boolean
        responded?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "crm_campaign_recipients_campaign_id_fkey",
          columns: ["tenant_id", "campaign_id"],
          isOneToOne: false,
          referencedRelation: "crm_campaigns",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "crm_campaign_recipients_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "crm_campaign_recipients_prospect_id_fkey",
          columns: ["tenant_id", "prospect_id"],
          isOneToOne: false,
          referencedRelation: "prospects",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "crm_campaign_recipients_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    crm_campaigns: {
      Row: {
        id: string
        tenant_id: string
        name: string
        description: string | null
        campaign_type: string
        status: string | null
        start_date: string | null
        end_date: string | null
        budget: number | null
        actual_cost: number | null
        target_audience: string | null
        segment_criteria: Json | null
        sent_count: number | null
        open_count: number | null
        click_count: number | null
        response_count: number | null
        conversion_count: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        description?: string
        campaign_type: string
        status?: string
        start_date?: string
        end_date?: string
        budget?: number
        actual_cost?: number
        target_audience?: string
        segment_criteria?: Json
        sent_count?: number
        open_count?: number
        click_count?: number
        response_count?: number
        conversion_count?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        description?: string
        campaign_type?: string
        status?: string
        start_date?: string
        end_date?: string
        budget?: number
        actual_cost?: number
        target_audience?: string
        segment_criteria?: Json
        sent_count?: number
        open_count?: number
        click_count?: number
        response_count?: number
        conversion_count?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "crm_campaigns_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    crm_forecasts: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        period: string
        sales_rep_id?: string
        target_amount?: number
        committed_amount?: number
        best_case_amount?: number
        pipeline_amount?: number
        closed_amount?: number
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        period?: string
        sales_rep_id?: string
        target_amount?: number
        committed_amount?: number
        best_case_amount?: number
        pipeline_amount?: number
        closed_amount?: number
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "crm_forecasts_sales_rep_id_fkey",
          columns: ["tenant_id", "sales_rep_id"],
          isOneToOne: false,
          referencedRelation: "sales_representatives",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "crm_forecasts_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    crm_opportunities: {
      Row: {
        id: string
        tenant_id: string
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
        tags: string[] | null
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        number: string
        customer_id?: string
        prospect_id?: string
        title: string
        description?: string
        stage?: string
        probability?: number
        expected_amount?: number
        expected_close_date?: string
        actual_amount?: number
        actual_close_date?: string
        sales_rep_id?: string
        source?: string
        lost_reason?: string
        tags?: string[]
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        number?: string
        customer_id?: string
        prospect_id?: string
        title?: string
        description?: string
        stage?: string
        probability?: number
        expected_amount?: number
        expected_close_date?: string
        actual_amount?: number
        actual_close_date?: string
        sales_rep_id?: string
        source?: string
        lost_reason?: string
        tags?: string[]
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "crm_opportunities_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "crm_opportunities_prospect_id_fkey",
          columns: ["tenant_id", "prospect_id"],
          isOneToOne: false,
          referencedRelation: "prospects",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "crm_opportunities_sales_rep_id_fkey",
          columns: ["tenant_id", "sales_rep_id"],
          isOneToOne: false,
          referencedRelation: "sales_representatives",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "crm_opportunities_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    crm_territories: {
      Row: {
        id: string
        tenant_id: string
        name: string
        code: string | null
        parent_id: string | null
        sales_rep_id: string | null
        regions: string[] | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        code?: string
        parent_id?: string
        sales_rep_id?: string
        regions?: string[]
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        code?: string
        parent_id?: string
        sales_rep_id?: string
        regions?: string[]
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "crm_territories_parent_id_fkey",
          columns: ["tenant_id", "parent_id"],
          isOneToOne: false,
          referencedRelation: "crm_territories",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "crm_territories_sales_rep_id_fkey",
          columns: ["tenant_id", "sales_rep_id"],
          isOneToOne: false,
          referencedRelation: "sales_representatives",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "crm_territories_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        tenant_id: string | null
        last_rate_date: string | null
        decimal_places: number | null
        rounding: number | null
        active: boolean | null
        position: string | null
      }
      Insert: {
        id?: string
        code: string
        name: string
        symbol?: string
        exchange_rate?: number
        is_base?: boolean
        created_at?: string
        tenant_id?: string
        last_rate_date?: string
        decimal_places?: number
        rounding?: number
        active?: boolean
        position?: string
      }
      Update: {
        id?: string
        code?: string
        name?: string
        symbol?: string
        exchange_rate?: number
        is_base?: boolean
        created_at?: string
        tenant_id?: string
        last_rate_date?: string
        decimal_places?: number
        rounding?: number
        active?: boolean
        position?: string
      }
      Relationships: [
        {
          foreignKeyName: "currencies_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: false,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    currency_revaluations: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        fiscal_year_id?: string
        period_date: string
        account_code: string
        third_party_code?: string
        currency: string
        original_rate?: number
        new_rate?: number
        original_amount?: number
        original_amount_eur?: number
        revalued_amount_eur?: number
        gain_loss?: number
        type: string
        status?: string
        entry_id?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        fiscal_year_id?: string
        period_date?: string
        account_code?: string
        third_party_code?: string
        currency?: string
        original_rate?: number
        new_rate?: number
        original_amount?: number
        original_amount_eur?: number
        revalued_amount_eur?: number
        gain_loss?: number
        type?: string
        status?: string
        entry_id?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "cr_entry_id_fkey",
          columns: ["tenant_id", "entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "cr_fiscal_year_id_fkey",
          columns: ["tenant_id", "fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "currency_revaluations_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    custom_report_templates: {
      Row: {
        id: string
        tenant_id: string
        name: string
        description: string | null
        report_type: string
        category: string
        columns: Json
        filters: Json
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
      Insert: {
        id?: string
        tenant_id: string
        name: string
        description?: string
        report_type: string
        category?: string
        columns?: Json
        filters?: Json
        group_by?: string
        sort_by?: string
        sort_order?: string
        page_orientation?: string
        page_size?: string
        header_text?: string
        footer_text?: string
        show_logo?: boolean
        show_date?: boolean
        show_page_numbers?: boolean
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        description?: string
        report_type?: string
        category?: string
        columns?: Json
        filters?: Json
        group_by?: string
        sort_by?: string
        sort_order?: string
        page_orientation?: string
        page_size?: string
        header_text?: string
        footer_text?: string
        show_logo?: boolean
        show_date?: boolean
        show_page_numbers?: boolean
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "custom_report_templates_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    customer_contacts: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        customer_id: string
        name: string
        role?: string
        email?: string
        phone?: string
        mobile?: string
        is_default?: boolean
        active?: boolean
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        customer_id?: string
        name?: string
        role?: string
        email?: string
        phone?: string
        mobile?: string
        is_default?: boolean
        active?: boolean
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "customer_contacts_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "customer_contacts_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        invoice_number: string | null
      }
      Insert: {
        id?: string
        number: string
        customer_id?: string
        invoice_id?: string
        payment_date?: string
        amount?: number
        method?: string
        bank_account_id?: string
        reference?: string
        status?: string
        created_at?: string
        tenant_id: string
        currency_code?: string
        exchange_rate?: number
        amount_currency?: number
        exchange_gain_loss?: number
        transferred_entry_id?: string
        invoice_number?: string
      }
      Update: {
        id?: string
        number?: string
        customer_id?: string
        invoice_id?: string
        payment_date?: string
        amount?: number
        method?: string
        bank_account_id?: string
        reference?: string
        status?: string
        created_at?: string
        tenant_id?: string
        currency_code?: string
        exchange_rate?: number
        amount_currency?: number
        exchange_gain_loss?: number
        transferred_entry_id?: string
        invoice_number?: string
      }
      Relationships: [
        {
          foreignKeyName: "customer_payments_bank_account_id_fkey",
          columns: ["tenant_id", "bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "customer_payments_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "customer_payments_invoice_id_fkey",
          columns: ["tenant_id", "invoice_id"],
          isOneToOne: false,
          referencedRelation: "invoices",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "customer_payments_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "customer_payments_transferred_entry_id_fkey",
          columns: ["tenant_id", "transferred_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
        email_settings: Json | null
        credit_used: number | null
        credit_blocked: boolean | null
        account_tiers: string | null
        account_collectif: string | null
        credit_policy: string | null
        credit_warning: boolean | null
        import_batch_id: string | null
        payment_term_id: string | null
        fiscal_position_id: string | null
      }
      Insert: {
        id?: string
        name: string
        email?: string
        phone?: string
        address?: string
        city?: string
        postal_code?: string
        country?: string
        vat_number?: string
        contact_name?: string
        balance?: number
        credit_limit?: number
        payment_terms?: string
        currency?: string
        active?: boolean
        created_at?: string
        updated_at?: string
        tenant_id: string
        legal_form?: string
        ape_code?: string
        naf_code?: string
        employee_count_range?: string
        revenue_range?: string
        payment_delay_avg?: number
        siret?: string
        sector_code?: string
        geographic_zone?: string
        parent_id?: string
        is_company?: boolean
        sales_rep_id?: string
        currency_code?: string
        bank_account_id?: string
        price_list_id?: string
        email_settings?: Json
        credit_used?: number
        credit_blocked?: boolean
        account_tiers?: string
        account_collectif?: string
        credit_policy?: string
        credit_warning?: boolean
        import_batch_id?: string
        payment_term_id?: string
        fiscal_position_id?: string
      }
      Update: {
        id?: string
        name?: string
        email?: string
        phone?: string
        address?: string
        city?: string
        postal_code?: string
        country?: string
        vat_number?: string
        contact_name?: string
        balance?: number
        credit_limit?: number
        payment_terms?: string
        currency?: string
        active?: boolean
        created_at?: string
        updated_at?: string
        tenant_id?: string
        legal_form?: string
        ape_code?: string
        naf_code?: string
        employee_count_range?: string
        revenue_range?: string
        payment_delay_avg?: number
        siret?: string
        sector_code?: string
        geographic_zone?: string
        parent_id?: string
        is_company?: boolean
        sales_rep_id?: string
        currency_code?: string
        bank_account_id?: string
        price_list_id?: string
        email_settings?: Json
        credit_used?: number
        credit_blocked?: boolean
        account_tiers?: string
        account_collectif?: string
        credit_policy?: string
        credit_warning?: boolean
        import_batch_id?: string
        payment_term_id?: string
        fiscal_position_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "customers_bank_account_id_fkey",
          columns: ["tenant_id", "bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "customers_fiscal_position_tenant_fkey",
          columns: ["tenant_id", "fiscal_position_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_positions",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "customers_parent_id_fkey",
          columns: ["tenant_id", "parent_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "customers_payment_term_tenant_fkey",
          columns: ["tenant_id", "payment_term_id"],
          isOneToOne: false,
          referencedRelation: "payment_terms",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "customers_price_list_id_fkey",
          columns: ["tenant_id", "price_list_id"],
          isOneToOne: false,
          referencedRelation: "price_lists",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "customers_sales_rep_id_fkey",
          columns: ["tenant_id", "sales_rep_id"],
          isOneToOne: false,
          referencedRelation: "sales_representatives",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "customers_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    dashboard_widgets: {
      Row: {
        id: string
        tenant_id: string
        user_id: string
        widget_type: string
        title: string
        config: Json | null
        position: number
        size: string
        visible: boolean | null
        created_at: string
        updated_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        user_id: string
        widget_type: string
        title: string
        config?: Json
        position?: number
        size?: string
        visible?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        user_id?: string
        widget_type?: string
        title?: string
        config?: Json
        position?: number
        size?: string
        visible?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "dashboard_widgets_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    data_import_logs: {
      Row: {
        id: string
        tenant_id: string
        import_type: string
        file_name: string | null
        file_size: number | null
        total_rows: number | null
        imported_rows: number | null
        rejected_rows: number | null
        error_details: Json | null
        status: string
        started_at: string | null
        completed_at: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        import_type: string
        file_name?: string
        file_size?: number
        total_rows?: number
        imported_rows?: number
        rejected_rows?: number
        error_details?: Json
        status?: string
        started_at?: string
        completed_at?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        import_type?: string
        file_name?: string
        file_size?: number
        total_rows?: number
        imported_rows?: number
        rejected_rows?: number
        error_details?: Json
        status?: string
        started_at?: string
        completed_at?: string
        created_at?: string
      }
      Relationships: [
      ]
    }
    deferred_printing_jobs: {
      Row: {
        id: string
        tenant_id: string
        job_name: string
        report_type: string
        parameters: Json
        scheduled_date: string
        status: string
        output_format: string
        output_data: string | null
        generated_at: string | null
        generated_by: string | null
        error_message: string | null
        created_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        job_name: string
        report_type: string
        parameters?: Json
        scheduled_date: string
        status?: string
        output_format?: string
        output_data?: string
        generated_at?: string
        generated_by?: string
        error_message?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        job_name?: string
        report_type?: string
        parameters?: Json
        scheduled_date?: string
        status?: string
        output_format?: string
        output_data?: string
        generated_at?: string
        generated_by?: string
        error_message?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "deferred_printing_jobs_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        lot_id: string | null
        serial_id: string | null
      }
      Insert: {
        id?: string
        delivery_note_id?: string
        product_id?: string
        description: string
        quantity?: number
        tenant_id: string
        ordered_quantity?: number
        invoiced_quantity?: number
        sales_order_line_id?: string
        lot_id?: string
        serial_id?: string
      }
      Update: {
        id?: string
        delivery_note_id?: string
        product_id?: string
        description?: string
        quantity?: number
        tenant_id?: string
        ordered_quantity?: number
        invoiced_quantity?: number
        sales_order_line_id?: string
        lot_id?: string
        serial_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "delivery_note_lines_delivery_note_id_fkey",
          columns: ["tenant_id", "delivery_note_id"],
          isOneToOne: false,
          referencedRelation: "delivery_notes",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "delivery_note_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "delivery_note_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "dnl_sales_order_line_id_fkey",
          columns: ["tenant_id", "sales_order_line_id"],
          isOneToOne: false,
          referencedRelation: "sales_order_lines",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
      Insert: {
        id?: string
        number: string
        customer_id?: string
        sales_order_id?: string
        delivery_date?: string
        status?: string
        carrier?: string
        tracking_number?: string
        notes?: string
        created_at?: string
        tenant_id: string
        validation_status?: string
        fully_invoiced?: boolean
        invoice_status?: string
      }
      Update: {
        id?: string
        number?: string
        customer_id?: string
        sales_order_id?: string
        delivery_date?: string
        status?: string
        carrier?: string
        tracking_number?: string
        notes?: string
        created_at?: string
        tenant_id?: string
        validation_status?: string
        fully_invoiced?: boolean
        invoice_status?: string
      }
      Relationships: [
        {
          foreignKeyName: "delivery_notes_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "delivery_notes_sales_order_id_fkey",
          columns: ["tenant_id", "sales_order_id"],
          isOneToOne: false,
          referencedRelation: "sales_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "delivery_notes_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    delivery_schedules: {
      Row: {
        id: string
        tenant_id: string
        customer_id: string | null
        product_id: string
        frequency: string | null
        quantity: number
        start_date: string
        end_date: string | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        customer_id?: string
        product_id: string
        frequency?: string
        quantity?: number
        start_date?: string
        end_date?: string
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        customer_id?: string
        product_id?: string
        frequency?: string
        quantity?: number
        start_date?: string
        end_date?: string
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "delivery_schedules_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "delivery_schedules_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    disputes: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        third_party_code: string
        invoice_ref?: string
        amount?: number
        reason: string
        status?: string
        resolution?: string
        opened_date?: string
        resolved_date?: string
        created_by?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        third_party_code?: string
        invoice_ref?: string
        amount?: number
        reason?: string
        status?: string
        resolution?: string
        opened_date?: string
        resolved_date?: string
        created_by?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "disputes_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    distribution_grill_lines: {
      Row: {
        id: string
        grill_id: string | null
        section_code: string
        percentage: number
        created_at: string
        tenant_id: string
      }
      Insert: {
        id?: string
        grill_id?: string
        section_code: string
        percentage?: number
        created_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        grill_id?: string
        section_code?: string
        percentage?: number
        created_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "distribution_grill_lines_grill_id_fkey",
          columns: ["tenant_id", "grill_id"],
          isOneToOne: false,
          referencedRelation: "distribution_grills",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "distribution_grill_lines_section_fkey",
          columns: ["tenant_id", "section_code"],
          isOneToOne: false,
          referencedRelation: "analytic_sections",
          referencedColumns: ["tenant_id", "code"]
        },
        {
          foreignKeyName: "distribution_grill_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    distribution_grills: {
      Row: {
        id: string
        tenant_id: string
        name: string
        description: string | null
        account_code: string
        journal_code: string | null
        active: boolean
        created_at: string
        updated_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        description?: string
        account_code: string
        journal_code?: string
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        description?: string
        account_code?: string
        journal_code?: string
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "distribution_grills_account_fkey",
          columns: ["tenant_id", "account_code"],
          isOneToOne: false,
          referencedRelation: "chart_accounts",
          referencedColumns: ["tenant_id", "code"]
        },
        {
          foreignKeyName: "distribution_grills_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    document_charges: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        document_type: string
        document_id: string
        charge_type: string
        label: string
        amount?: number
        vat_rate?: number
        vat_amount?: number
        total_amount?: number
        supplier_id?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        document_type?: string
        document_id?: string
        charge_type?: string
        label?: string
        amount?: number
        vat_rate?: number
        vat_amount?: number
        total_amount?: number
        supplier_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "document_charges_supplier_id_fkey",
          columns: ["tenant_id", "supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "document_charges_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    document_distribution_logs: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        batch_id?: string
        employee_document_id?: string
        employee_id: string
        document_type?: string
        period?: string
        distributed_at?: string
        acknowledged_at?: string
        status?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        batch_id?: string
        employee_document_id?: string
        employee_id?: string
        document_type?: string
        period?: string
        distributed_at?: string
        acknowledged_at?: string
        status?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "document_distribution_logs_employee_document_id_fkey",
          columns: ["tenant_id", "employee_document_id"],
          isOneToOne: false,
          referencedRelation: "employee_documents",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "document_distribution_logs_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "document_distribution_logs_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    document_effects: {
      Row: {
        id: string
        tenant_id: string | null
        document_type: string
        evenement: string
        effet: string
        ecrit_comptable: boolean
        journal_code: string | null
        touche_stock: boolean
        touche_paie: boolean
        reversible: boolean
        obligatoire: boolean
        actif: boolean
        note: string | null
        created_at: string
      }
      Insert: {
        id?: string
        tenant_id?: string
        document_type: string
        evenement: string
        effet: string
        ecrit_comptable?: boolean
        journal_code?: string
        touche_stock?: boolean
        touche_paie?: boolean
        reversible?: boolean
        obligatoire?: boolean
        actif?: boolean
        note?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        document_type?: string
        evenement?: string
        effet?: string
        ecrit_comptable?: boolean
        journal_code?: string
        touche_stock?: boolean
        touche_paie?: boolean
        reversible?: boolean
        obligatoire?: boolean
        actif?: boolean
        note?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "document_effects_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: false,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    document_links: {
      Row: {
        id: string
        tenant_id: string
        amont_type: string
        amont_id: string
        amont_ligne_id: string | null
        aval_type: string
        aval_id: string
        aval_ligne_id: string | null
        link_type: string
        effet: string
        payload: Json
        created_by: string | null
        created_at: string
        etat: string
        tour: number
        ferme_le: string | null
        ferme_par: string | null
        motif: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        amont_type: string
        amont_id: string
        amont_ligne_id?: string
        aval_type: string
        aval_id: string
        aval_ligne_id?: string
        link_type: string
        effet: string
        payload?: Json
        created_by?: string
        created_at?: string
        etat?: string
        tour?: number
        ferme_le?: string
        ferme_par?: string
        motif?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        amont_type?: string
        amont_id?: string
        amont_ligne_id?: string
        aval_type?: string
        aval_id?: string
        aval_ligne_id?: string
        link_type?: string
        effet?: string
        payload?: Json
        created_by?: string
        created_at?: string
        etat?: string
        tour?: number
        ferme_le?: string
        ferme_par?: string
        motif?: string
      }
      Relationships: [
        {
          foreignKeyName: "document_links_amont_type_fk",
          columns: ["amont_type"],
          isOneToOne: true,
          referencedRelation: "chain_document_types",
          referencedColumns: ["code"]
        },
        {
          foreignKeyName: "document_links_aval_type_fk",
          columns: ["aval_type"],
          isOneToOne: true,
          referencedRelation: "chain_document_types",
          referencedColumns: ["code"]
        },
        {
          foreignKeyName: "document_links_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    document_number_sequences: {
      Row: {
        id: string
        tenant_id: string
        prefix: string
        next_number: number
        created_at: string | null
        updated_at: string | null
        fiscal_year_id: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        prefix: string
        next_number?: number
        created_at?: string
        updated_at?: string
        fiscal_year_id?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        prefix?: string
        next_number?: number
        created_at?: string
        updated_at?: string
        fiscal_year_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "document_number_sequences_fiscal_year_id_fkey",
          columns: ["tenant_id", "fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    document_shares: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        document_type: string
        document_id: string
        shared_with_email: string
        share_token: string
        share_url?: string
        expires_at?: string
        viewed?: boolean
        viewed_at?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        document_type?: string
        document_id?: string
        shared_with_email?: string
        share_token?: string
        share_url?: string
        expires_at?: string
        viewed?: boolean
        viewed_at?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "document_shares_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    document_templates: {
      Row: {
        id: string
        tenant_id: string
        name: string
        document_type: string
        logo_url: string | null
        primary_color: string | null
        secondary_color: string | null
        template_config: Json | null
        is_default: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        document_type: string
        logo_url?: string
        primary_color?: string
        secondary_color?: string
        template_config?: Json
        is_default?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        document_type?: string
        logo_url?: string
        primary_color?: string
        secondary_color?: string
        template_config?: Json
        is_default?: boolean
        created_at?: string
      }
      Relationships: [
      ]
    }
    document_transformations: {
      Row: {
        id: string
        tenant_id: string
        source_type: string
        source_id: string
        target_type: string
        target_id: string
        transformation_type: string
        transformed_by: string | null
        transformed_at: string | null
        notes: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        source_type: string
        source_id: string
        target_type: string
        target_id: string
        transformation_type: string
        transformed_by?: string
        transformed_at?: string
        notes?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        source_type?: string
        source_id?: string
        target_type?: string
        target_id?: string
        transformation_type?: string
        transformed_by?: string
        transformed_at?: string
        notes?: string
      }
      Relationships: [
        {
          foreignKeyName: "document_transformations_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    domain_events: {
      Row: {
        id: number
        tenant_id: string
        event_name: string
        aggregate_type: string
        aggregate_id: string
        payload: Json
        actor_id: string | null
        created_at: string
      }
      Insert: {
        id?: number
        tenant_id: string
        event_name: string
        aggregate_type: string
        aggregate_id: string
        payload?: Json
        actor_id?: string
        created_at?: string
      }
      Update: {
        id?: number
        tenant_id?: string
        event_name?: string
        aggregate_type?: string
        aggregate_id?: string
        payload?: Json
        actor_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "domain_events_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    dpae_records: {
      Row: {
        id: string
        tenant_id: string
        employee_id: string
        hire_date: string
        contract_type: string | null
        position: string | null
        status: string | null
        transmitted_at: string | null
        response_code: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        hire_date: string
        contract_type?: string
        position?: string
        status?: string
        transmitted_at?: string
        response_code?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        hire_date?: string
        contract_type?: string
        position?: string
        status?: string
        transmitted_at?: string
        response_code?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "dpae_records_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    dsn_declarations: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        period: string
        type?: string
        status?: string
        file_url?: string
        generated_at?: string
        transmitted_at?: string
        response_code?: string
        response_message?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        period?: string
        type?: string
        status?: string
        file_url?: string
        generated_at?: string
        transmitted_at?: string
        response_code?: string
        response_message?: string
        created_at?: string
      }
      Relationships: [
      ]
    }
    electronic_signatures: {
      Row: {
        id: string
        tenant_id: string
        document_type: string
        document_id: string
        signer_name: string
        signer_email: string | null
        signature_hash: string | null
        signature_data: string | null
        ip_address: string | null
        signed_at: string | null
        created_at: string | null
        provider: string | null
        provider_signature_id: string | null
        status: string | null
        signers: Json | null
        initiated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        document_type: string
        document_id: string
        signer_name: string
        signer_email?: string
        signature_hash?: string
        signature_data?: string
        ip_address?: string
        signed_at?: string
        created_at?: string
        provider?: string
        provider_signature_id?: string
        status?: string
        signers?: Json
        initiated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        document_type?: string
        document_id?: string
        signer_name?: string
        signer_email?: string
        signature_hash?: string
        signature_data?: string
        ip_address?: string
        signed_at?: string
        created_at?: string
        provider?: string
        provider_signature_id?: string
        status?: string
        signers?: Json
        initiated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "electronic_signatures_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    email_templates: {
      Row: {
        id: string
        tenant_id: string
        template_key: string
        subject: string
        body_html: string
        body_text: string | null
        variables: Json
        locale: string
        active: boolean
        created_at: string
        updated_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        template_key: string
        subject: string
        body_html: string
        body_text?: string
        variables?: Json
        locale?: string
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        template_key?: string
        subject?: string
        body_html?: string
        body_text?: string
        variables?: Json
        locale?: string
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "email_templates_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    employee_absence_days: {
      Row: {
        tenant_id: string
        employee_id: string
        day: string
        absence_kind: string
        origin: string
        origin_id: string | null
        justification_state: string
        blocks_work: boolean
        allows_expenses: boolean
        paid: boolean
        pay_rule_code: string | null
        created_at: string
        day_uid: string | null
      }
      Insert: {
        tenant_id: string
        employee_id: string
        day: string
        absence_kind: string
        origin: string
        origin_id?: string
        justification_state?: string
        blocks_work?: boolean
        allows_expenses?: boolean
        paid?: boolean
        pay_rule_code?: string
        created_at?: string
        day_uid?: string
      }
      Update: {
        tenant_id?: string
        employee_id?: string
        day?: string
        absence_kind?: string
        origin?: string
        origin_id?: string
        justification_state?: string
        blocks_work?: boolean
        allows_expenses?: boolean
        paid?: boolean
        pay_rule_code?: string
        created_at?: string
        day_uid?: string
      }
      Relationships: [
        {
          foreignKeyName: "employee_absence_days_employee_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    employee_activity_logs: {
      Row: {
        id: string
        tenant_id: string
        employee_id: string
        activity_type: string
        description: string | null
        metadata: Json | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        activity_type: string
        description?: string
        metadata?: Json
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        activity_type?: string
        description?: string
        metadata?: Json
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "employee_activity_logs_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "employee_activity_logs_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    employee_documents: {
      Row: {
        id: string
        tenant_id: string
        employee_id: string
        document_type: string
        file_url: string
        file_name: string | null
        distributed_at: string | null
        acknowledged_at: string | null
        created_at: string | null
        title: string
        file_size: number | null
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
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        document_type: string
        file_url: string
        file_name?: string
        distributed_at?: string
        acknowledged_at?: string
        created_at?: string
        title: string
        file_size?: number
        mime_type?: string
        period?: string
        uploaded_by?: string
        visible_to_employee?: boolean
        requires_acknowledgment?: boolean
        acknowledged?: boolean
        e_signed?: boolean
        e_signed_at?: string
        e_signature_hash?: string
        archived?: boolean
        archive_date?: string
        retention_years?: number
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        document_type?: string
        file_url?: string
        file_name?: string
        distributed_at?: string
        acknowledged_at?: string
        created_at?: string
        title?: string
        file_size?: number
        mime_type?: string
        period?: string
        uploaded_by?: string
        visible_to_employee?: boolean
        requires_acknowledgment?: boolean
        acknowledged?: boolean
        e_signed?: boolean
        e_signed_at?: string
        e_signature_hash?: string
        archived?: boolean
        archive_date?: string
        retention_years?: number
      }
      Relationships: [
        {
          foreignKeyName: "employee_documents_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    employee_exit_processes: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        exit_date: string
        exit_reason: string
        step?: number
        status?: string
        cp_indemnity?: number
        rtt_indemnity?: number
        recovery_indemnity?: number
        bonus_amount?: number
        advance_deduction?: number
        overtime_amount?: number
        total_gross?: number
        total_net?: number
        work_certificate_url?: string
        settlement_receipt_url?: string
        pole_emploi_attestation_url?: string
        dsn_exit_url?: string
        documents_generated?: boolean
        dsn_exit_generated?: boolean
        dsn_exit_transmitted?: boolean
        exit_payslip_id?: string
        notes?: string
        created_at?: string
        completed_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        exit_date?: string
        exit_reason?: string
        step?: number
        status?: string
        cp_indemnity?: number
        rtt_indemnity?: number
        recovery_indemnity?: number
        bonus_amount?: number
        advance_deduction?: number
        overtime_amount?: number
        total_gross?: number
        total_net?: number
        work_certificate_url?: string
        settlement_receipt_url?: string
        pole_emploi_attestation_url?: string
        dsn_exit_url?: string
        documents_generated?: boolean
        dsn_exit_generated?: boolean
        dsn_exit_transmitted?: boolean
        exit_payslip_id?: string
        notes?: string
        created_at?: string
        completed_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "eep_exit_payslip_id_fkey",
          columns: ["tenant_id", "exit_payslip_id"],
          isOneToOne: false,
          referencedRelation: "pay_slips",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "employee_exit_processes_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "employee_exit_processes_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    employee_objectives: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        campaign_id?: string
        title: string
        description?: string
        target_value?: number
        current_value?: number
        unit?: string
        period?: string
        frequency?: string
        status?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        campaign_id?: string
        title?: string
        description?: string
        target_value?: number
        current_value?: number
        unit?: string
        period?: string
        frequency?: string
        status?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "employee_objectives_campaign_id_fkey",
          columns: ["tenant_id", "campaign_id"],
          isOneToOne: false,
          referencedRelation: "interview_campaigns",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "employee_objectives_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "employee_objectives_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        withholding_tax_rate: number | null
        withholding_rate_source: string | null
        weekly_hours: number | null
        default_start_time: string | null
        default_end_time: string | null
        import_batch_id: string | null
        first_name: string | null
        last_name: string | null
        base_salary: number | null
        collective_agreement_id: string | null
        classification_id: string | null
        seniority_date: string | null
        auth_user_id: string | null
        gender: string | null
        payroll_category: string
      }
      Insert: {
        id?: string
        name: string
        email?: string
        phone?: string
        position?: string
        department?: string
        salary?: number
        hire_date?: string
        status?: string
        created_at?: string
        updated_at?: string
        tenant_id: string
        employee_number?: string
        social_security_number?: string
        birth_date?: string
        address?: string
        city?: string
        postal_code?: string
        contract_type?: string
        contract_end_date?: string
        emergency_contact_name?: string
        emergency_contact_phone?: string
        emergency_contact_relation?: string
        photo_url?: string
        bank_iban?: string
        bank_bic?: string
        bank_account_holder?: string
        transport_mode?: string
        transport_cost?: number
        meal_voucher_count?: number
        meal_voucher_value?: number
        withholding_tax_rate?: number
        withholding_rate_source?: string
        weekly_hours?: number
        default_start_time?: string
        default_end_time?: string
        import_batch_id?: string
        first_name?: string
        last_name?: string
        base_salary?: number
        collective_agreement_id?: string
        classification_id?: string
        seniority_date?: string
        auth_user_id?: string
        gender?: string
        payroll_category?: string
      }
      Update: {
        id?: string
        name?: string
        email?: string
        phone?: string
        position?: string
        department?: string
        salary?: number
        hire_date?: string
        status?: string
        created_at?: string
        updated_at?: string
        tenant_id?: string
        employee_number?: string
        social_security_number?: string
        birth_date?: string
        address?: string
        city?: string
        postal_code?: string
        contract_type?: string
        contract_end_date?: string
        emergency_contact_name?: string
        emergency_contact_phone?: string
        emergency_contact_relation?: string
        photo_url?: string
        bank_iban?: string
        bank_bic?: string
        bank_account_holder?: string
        transport_mode?: string
        transport_cost?: number
        meal_voucher_count?: number
        meal_voucher_value?: number
        withholding_tax_rate?: number
        withholding_rate_source?: string
        weekly_hours?: number
        default_start_time?: string
        default_end_time?: string
        import_batch_id?: string
        first_name?: string
        last_name?: string
        base_salary?: number
        collective_agreement_id?: string
        classification_id?: string
        seniority_date?: string
        auth_user_id?: string
        gender?: string
        payroll_category?: string
      }
      Relationships: [
        {
          foreignKeyName: "employees_classification_id_fkey",
          columns: ["tenant_id", "classification_id"],
          isOneToOne: false,
          referencedRelation: "collective_classifications",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "employees_collective_agreement_id_fkey",
          columns: ["tenant_id", "collective_agreement_id"],
          isOneToOne: false,
          referencedRelation: "collective_agreements",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "employees_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    entry_templates: {
      Row: {
        id: string
        name: string
        journal_code: string | null
        description: string | null
        template_lines: Json | null
        is_default: boolean | null
        active: boolean | null
        created_at: string | null
        tenant_id: string
        counterpart_account: string | null
        payment_terms: string | null
      }
      Insert: {
        id?: string
        name: string
        journal_code?: string
        description?: string
        template_lines?: Json
        is_default?: boolean
        active?: boolean
        created_at?: string
        tenant_id: string
        counterpart_account?: string
        payment_terms?: string
      }
      Update: {
        id?: string
        name?: string
        journal_code?: string
        description?: string
        template_lines?: Json
        is_default?: boolean
        active?: boolean
        created_at?: string
        tenant_id?: string
        counterpart_account?: string
        payment_terms?: string
      }
      Relationships: [
        {
          foreignKeyName: "entry_templates_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    etat_rapprochement: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        bank_account_id?: string
        account_code: string
        period_start: string
        period_end: string
        bank_balance?: number
        book_balance?: number
        difference?: number
        reconciled_items?: number
        unreconciled_items?: number
        generated_at?: string
        generated_by?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        bank_account_id?: string
        account_code?: string
        period_start?: string
        period_end?: string
        bank_balance?: number
        book_balance?: number
        difference?: number
        reconciled_items?: number
        unreconciled_items?: number
        generated_at?: string
        generated_by?: string
      }
      Relationships: [
        {
          foreignKeyName: "er_bank_account_id_fkey",
          columns: ["tenant_id", "bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "etat_rapprochement_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    exchange_gain_loss_entries: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        payment_id?: string
        invoice_id?: string
        type: string
        amount?: number
        exchange_rate_original?: number
        exchange_rate_payment?: number
        account_gain_code?: string
        account_loss_code?: string
        journal_entry_id?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        payment_id?: string
        invoice_id?: string
        type?: string
        amount?: number
        exchange_rate_original?: number
        exchange_rate_payment?: number
        account_gain_code?: string
        account_loss_code?: string
        journal_entry_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "exchange_gain_loss_entries_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "exgl_invoice_id_fkey",
          columns: ["tenant_id", "invoice_id"],
          isOneToOne: false,
          referencedRelation: "invoices",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "exgl_journal_entry_id_fkey",
          columns: ["tenant_id", "journal_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id?: string
        base_currency: string
        quote_currency: string
        rate: number
        rate_date: string
        source?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        base_currency?: string
        quote_currency?: string
        rate?: number
        rate_date?: string
        source?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "exchange_rates_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: false,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    expense_categories: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        code: string
        label: string
        account_code?: string
        vat_rate?: number
        max_amount?: number
        max_monthly?: number
        requires_receipt?: boolean
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        label?: string
        account_code?: string
        vat_rate?: number
        max_amount?: number
        max_monthly?: number
        requires_receipt?: boolean
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "expense_categories_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    expense_report_lines: {
      Row: {
        id: string
        tenant_id: string
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
        ocr_data: Json | null
        ocr_processed: boolean | null
        ceiling_exceeded: boolean | null
        mission_absence_day: string | null
        mission_absence_employee_id: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        expense_report_id: string
        date: string
        description: string
        category?: string
        amount?: number
        vat_rate?: number
        vat_amount?: number
        receipt_url?: string
        created_at?: string
        category_id?: string
        amount_ht?: number
        amount_ttc?: number
        ocr_data?: Json
        ocr_processed?: boolean
        ceiling_exceeded?: boolean
        mission_absence_day?: string
        mission_absence_employee_id?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        expense_report_id?: string
        date?: string
        description?: string
        category?: string
        amount?: number
        vat_rate?: number
        vat_amount?: number
        receipt_url?: string
        created_at?: string
        category_id?: string
        amount_ht?: number
        amount_ttc?: number
        ocr_data?: Json
        ocr_processed?: boolean
        ceiling_exceeded?: boolean
        mission_absence_day?: string
        mission_absence_employee_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "expense_report_lines_category_id_fkey",
          columns: ["tenant_id", "category_id"],
          isOneToOne: false,
          referencedRelation: "expense_categories",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "expense_report_lines_expense_report_id_fkey",
          columns: ["tenant_id", "expense_report_id"],
          isOneToOne: false,
          referencedRelation: "expense_reports",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "expense_report_lines_mission_fkey",
          columns: ["tenant_id", "mission_absence_employee_id", "mission_absence_day"],
          isOneToOne: false,
          referencedRelation: "employee_absence_days",
          referencedColumns: ["tenant_id", "employee_id", "day"]
        },
      ]
    }
    expense_reports: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        number: string
        period?: string
        total_amount?: number
        total_vat?: number
        status?: string
        submitted_at?: string
        approved_by?: string
        approved_at?: string
        notes?: string
        created_at?: string
        manager_id?: string
        manager_comment?: string
        reimbursement_date?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        number?: string
        period?: string
        total_amount?: number
        total_vat?: number
        status?: string
        submitted_at?: string
        approved_by?: string
        approved_at?: string
        notes?: string
        created_at?: string
        manager_id?: string
        manager_comment?: string
        reimbursement_date?: string
      }
      Relationships: [
        {
          foreignKeyName: "er_manager_id_fkey",
          columns: ["tenant_id", "manager_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "expense_reports_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    extourne_log: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        original_entry_id: string
        extourne_entry_id: string
        extourne_date: string
        reason?: string
        journal_code?: string
        total_debit?: number
        total_credit?: number
        status?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        original_entry_id?: string
        extourne_entry_id?: string
        extourne_date?: string
        reason?: string
        journal_code?: string
        total_debit?: number
        total_credit?: number
        status?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "el_extourne_entry_id_fkey",
          columns: ["tenant_id", "extourne_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "el_original_entry_id_fkey",
          columns: ["tenant_id", "original_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "extourne_log_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    fec_attestations: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        fiscal_year_id: string
        attestation_number: string
        attestation_date: string
        fec_type?: string
        entry_count?: number
        total_debit?: number
        total_credit?: number
        file_name?: string
        file_content?: string
        status?: string
        generated_by?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        fiscal_year_id?: string
        attestation_number?: string
        attestation_date?: string
        fec_type?: string
        entry_count?: number
        total_debit?: number
        total_credit?: number
        file_name?: string
        file_content?: string
        status?: string
        generated_by?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "fec_attest_fiscal_year_id_fkey",
          columns: ["tenant_id", "fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "fec_attestations_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    fiscal_backups: {
      Row: {
        id: string
        tenant_id: string
        fiscal_year_id: string | null
        backup_type: string
        status: string
        file_url: string | null
        file_size: number | null
        created_by: string | null
        created_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        fiscal_year_id?: string
        backup_type?: string
        status?: string
        file_url?: string
        file_size?: number
        created_by?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        fiscal_year_id?: string
        backup_type?: string
        status?: string
        file_url?: string
        file_size?: number
        created_by?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "fiscal_backups_fiscal_year_id_fkey",
          columns: ["tenant_id", "fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "fiscal_backups_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        fiscal_year_id?: string
        period_number: number
        period_label: string
        start_date: string
        end_date: string
        status?: string
        created_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        fiscal_year_id?: string
        period_number?: number
        period_label?: string
        start_date?: string
        end_date?: string
        status?: string
        created_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "fiscal_periods_fiscal_year_id_fkey",
          columns: ["tenant_id", "fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "fiscal_periods_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    fiscal_position_mappings: {
      Row: {
        id: string
        tenant_id: string
        fiscal_position_id: string
        source_tax_id: string | null
        target_tax_id: string | null
        source_account_code: string | null
        target_account_code: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        fiscal_position_id: string
        source_tax_id?: string
        target_tax_id?: string
        source_account_code?: string
        target_account_code?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        fiscal_position_id?: string
        source_tax_id?: string
        target_tax_id?: string
        source_account_code?: string
        target_account_code?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "fiscal_position_mappings_fiscal_position_id_fkey",
          columns: ["tenant_id", "fiscal_position_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_positions",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "fiscal_position_mappings_source_tax_id_fkey",
          columns: ["tenant_id", "source_tax_id"],
          isOneToOne: false,
          referencedRelation: "tax_rates",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "fiscal_position_mappings_target_tax_id_fkey",
          columns: ["tenant_id", "target_tax_id"],
          isOneToOne: false,
          referencedRelation: "tax_rates",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "fiscal_position_mappings_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    fiscal_positions: {
      Row: {
        id: string
        tenant_id: string
        name: string
        country_code: string | null
        country_group_id: string | null
        zip_from: string | null
        zip_to: string | null
        auto_apply: boolean | null
        active: boolean | null
        created_at: string | null
        regime: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        country_code?: string
        country_group_id?: string
        zip_from?: string
        zip_to?: string
        auto_apply?: boolean
        active?: boolean
        created_at?: string
        regime?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        country_code?: string
        country_group_id?: string
        zip_from?: string
        zip_to?: string
        auto_apply?: boolean
        active?: boolean
        created_at?: string
        regime?: string
      }
      Relationships: [
        {
          foreignKeyName: "fiscal_positions_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        closing_result: number | null
        result_allocated_at: string | null
        result_allocation_entry_id: string | null
      }
      Insert: {
        id?: string
        code: string
        start_date: string
        end_date: string
        status?: string
        closed_at?: string
        closed_by?: string
        created_at?: string
        tenant_id: string
        closing_result?: number
        result_allocated_at?: string
        result_allocation_entry_id?: string
      }
      Update: {
        id?: string
        code?: string
        start_date?: string
        end_date?: string
        status?: string
        closed_at?: string
        closed_by?: string
        created_at?: string
        tenant_id?: string
        closing_result?: number
        result_allocated_at?: string
        result_allocation_entry_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "fiscal_years_closed_by_fkey",
          columns: ["tenant_id", "closed_by"],
          isOneToOne: false,
          referencedRelation: "users",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "fiscal_years_result_allocation_entry_id_fkey",
          columns: ["tenant_id", "result_allocation_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "fiscal_years_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    fixed_asset_components: {
      Row: {
        id: string
        tenant_id: string
        fixed_asset_id: string
        name: string
        acquisition_value: number
        depreciation_method: string | null
        useful_life_years: number
        salvage_value: number | null
        start_date: string
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        fixed_asset_id: string
        name: string
        acquisition_value: number
        depreciation_method?: string
        useful_life_years: number
        salvage_value?: number
        start_date: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        fixed_asset_id?: string
        name?: string
        acquisition_value?: number
        depreciation_method?: string
        useful_life_years?: number
        salvage_value?: number
        start_date?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "fixed_asset_components_fixed_asset_id_fkey",
          columns: ["tenant_id", "fixed_asset_id"],
          isOneToOne: false,
          referencedRelation: "fixed_assets",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
      Insert: {
        id?: string
        name: string
        code?: string
        category?: string
        purchase_date?: string
        purchase_value?: number
        current_value?: number
        depreciation_method?: string
        useful_life_years?: number
        residual_value?: number
        status?: string
        created_at?: string
        updated_at?: string
        tenant_id: string
        asset_type?: string
        parent_asset_id?: string
        family_id?: string
        asset_number?: string
        lease_start_date?: string
        lease_end_date?: string
        lease_monthly_payment?: number
        purchase_entry_id?: string
        account_asset_code?: string
        account_depreciation_code?: string
        account_expense_depreciation_code?: string
        journal_id?: string
        partner_id?: string
        currency_code?: string
      }
      Update: {
        id?: string
        name?: string
        code?: string
        category?: string
        purchase_date?: string
        purchase_value?: number
        current_value?: number
        depreciation_method?: string
        useful_life_years?: number
        residual_value?: number
        status?: string
        created_at?: string
        updated_at?: string
        tenant_id?: string
        asset_type?: string
        parent_asset_id?: string
        family_id?: string
        asset_number?: string
        lease_start_date?: string
        lease_end_date?: string
        lease_monthly_payment?: number
        purchase_entry_id?: string
        account_asset_code?: string
        account_depreciation_code?: string
        account_expense_depreciation_code?: string
        journal_id?: string
        partner_id?: string
        currency_code?: string
      }
      Relationships: [
        {
          foreignKeyName: "fa_journal_id_fkey",
          columns: ["tenant_id", "journal_id"],
          isOneToOne: false,
          referencedRelation: "journals",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "fixed_assets_family_id_fkey",
          columns: ["tenant_id", "family_id"],
          isOneToOne: false,
          referencedRelation: "asset_families",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "fixed_assets_parent_asset_id_fkey",
          columns: ["tenant_id", "parent_asset_id"],
          isOneToOne: false,
          referencedRelation: "fixed_assets",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "fixed_assets_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    fusion_logs: {
      Row: {
        id: string
        tenant_id: string
        source_account_code: string
        target_account_code: string
        lines_moved: number
        fused_by: string | null
        fused_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        source_account_code: string
        target_account_code: string
        lines_moved?: number
        fused_by?: string
        fused_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        source_account_code?: string
        target_account_code?: string
        lines_moved?: number
        fused_by?: string
        fused_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "fusion_logs_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    future_accounting_movements: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        description: string
        account_code: string
        third_party_id?: string
        amount?: number
        movement_type: string
        expected_date: string
        source_type?: string
        source_id?: string
        incorporated?: boolean
        incorporated_entry_id?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        description?: string
        account_code?: string
        third_party_id?: string
        amount?: number
        movement_type?: string
        expected_date?: string
        source_type?: string
        source_id?: string
        incorporated?: boolean
        incorporated_entry_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "fam_incorporated_entry_id_fkey",
          columns: ["tenant_id", "incorporated_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
        lot_id: string | null
        serial_id: string | null
        purchase_order_line_id: string | null
      }
      Insert: {
        id?: string
        goods_receipt_id?: string
        product_id?: string
        description: string
        quantity_ordered?: number
        quantity_received?: number
        tenant_id: string
        lot_id?: string
        serial_id?: string
        purchase_order_line_id?: string
      }
      Update: {
        id?: string
        goods_receipt_id?: string
        product_id?: string
        description?: string
        quantity_ordered?: number
        quantity_received?: number
        tenant_id?: string
        lot_id?: string
        serial_id?: string
        purchase_order_line_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "goods_receipt_lines_goods_receipt_id_fkey",
          columns: ["tenant_id", "goods_receipt_id"],
          isOneToOne: false,
          referencedRelation: "goods_receipts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "goods_receipt_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "goods_receipt_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "grl_purchase_order_line_id_fkey",
          columns: ["tenant_id", "purchase_order_line_id"],
          isOneToOne: false,
          referencedRelation: "purchase_order_lines",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
        warehouse_id: string | null
      }
      Insert: {
        id?: string
        number: string
        supplier_id?: string
        purchase_order_id?: string
        receipt_date?: string
        status?: string
        notes?: string
        created_at?: string
        tenant_id: string
        warehouse_id?: string
      }
      Update: {
        id?: string
        number?: string
        supplier_id?: string
        purchase_order_id?: string
        receipt_date?: string
        status?: string
        notes?: string
        created_at?: string
        tenant_id?: string
        warehouse_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "goods_receipts_purchase_order_id_fkey",
          columns: ["tenant_id", "purchase_order_id"],
          isOneToOne: false,
          referencedRelation: "purchase_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "goods_receipts_supplier_id_fkey",
          columns: ["tenant_id", "supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "goods_receipts_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "goods_receipts_warehouse_id_fkey",
          columns: ["tenant_id", "warehouse_id"],
          isOneToOne: false,
          referencedRelation: "warehouses",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    grid_templates: {
      Row: {
        id: string
        tenant_id: string
        code: string
        name: string
        description: string | null
        journal_code: string | null
        columns_config: Json
        default_account: string | null
        is_active: boolean | null
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        code: string
        name: string
        description?: string
        journal_code?: string
        columns_config?: Json
        default_account?: string
        is_active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        name?: string
        description?: string
        journal_code?: string
        columns_config?: Json
        default_account?: string
        is_active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "grid_templates_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    group_members: {
      Row: {
        id: string
        group_id: string
        tenant_id: string
        member_type: string
        ownership_pct: number
        consolidation_method: string
        joined_at: string
      }
      Insert: {
        id?: string
        group_id: string
        tenant_id: string
        member_type?: string
        ownership_pct?: number
        consolidation_method?: string
        joined_at?: string
      }
      Update: {
        id?: string
        group_id?: string
        tenant_id?: string
        member_type?: string
        ownership_pct?: number
        consolidation_method?: string
        joined_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "group_members_group_id_fkey",
          columns: ["group_id"],
          isOneToOne: true,
          referencedRelation: "groups",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "group_members_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    groups: {
      Row: {
        id: string
        name: string
        created_by: string
        created_at: string
        updated_at: string
      }
      Insert: {
        id?: string
        name: string
        created_by: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        name?: string
        created_by?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
      ]
    }
    honorarium_records: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        employee_id?: string
        recipient_name: string
        recipient_type?: string
        period?: string
        amount?: number
        description?: string
        accounting_entry_id?: string
        status?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        recipient_name?: string
        recipient_type?: string
        period?: string
        amount?: number
        description?: string
        accounting_entry_id?: string
        status?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "honorarium_records_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "honorarium_records_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "hr_accounting_entry_id_fkey",
          columns: ["tenant_id", "accounting_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    idempotency_records: {
      Row: {
        id: string
        tenant_id: string
        idempotency_key: string
        response: Json
        status: number
        expires_at: string
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        idempotency_key: string
        response: Json
        status: number
        expires_at: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        idempotency_key?: string
        response?: Json
        status?: number
        expires_at?: string
        created_at?: string
      }
      Relationships: [
      ]
    }
    ifrs_adjustments: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        fiscal_year_id?: string
        adjustment_type: string
        account_code: string
        counter_account_code: string
        description: string
        amount?: number
        adjustment_date: string
        ifrs_standard?: string
        journal_entry_id?: string
        status?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        fiscal_year_id?: string
        adjustment_type?: string
        account_code?: string
        counter_account_code?: string
        description?: string
        amount?: number
        adjustment_date?: string
        ifrs_standard?: string
        journal_entry_id?: string
        status?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "ifrs_adjustments_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "ifrs_fiscal_year_id_fkey",
          columns: ["tenant_id", "fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "ifrs_journal_entry_id_fkey",
          columns: ["tenant_id", "journal_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    ijss_history: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        work_stoppage_id: string
        employee_id: string
        period: string
        ijss_net_received?: number
        ijss_brut_calculated?: number
        days_paid?: number
        pas_amount?: number
        pas_rate?: number
        integrated_in_payslip?: boolean
        payslip_id?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        work_stoppage_id?: string
        employee_id?: string
        period?: string
        ijss_net_received?: number
        ijss_brut_calculated?: number
        days_paid?: number
        pas_amount?: number
        pas_rate?: number
        integrated_in_payslip?: boolean
        payslip_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "ijss_history_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "ijss_history_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "ijss_history_work_stoppage_id_fkey",
          columns: ["tenant_id", "work_stoppage_id"],
          isOneToOne: false,
          referencedRelation: "work_stoppages",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "ijss_payslip_id_fkey",
          columns: ["tenant_id", "payslip_id"],
          isOneToOne: false,
          referencedRelation: "pay_slips",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    import_batches: {
      Row: {
        id: string
        tenant_id: string
        target_table: string
        file_name: string | null
        total_rows: number | null
        valid_rows: number | null
        invalid_rows: number | null
        status: string
        error_report: Json | null
        created_by: string | null
        created_at: string | null
        validated_at: string | null
        completed_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        target_table: string
        file_name?: string
        total_rows?: number
        valid_rows?: number
        invalid_rows?: number
        status?: string
        error_report?: Json
        created_by?: string
        created_at?: string
        validated_at?: string
        completed_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        target_table?: string
        file_name?: string
        total_rows?: number
        valid_rows?: number
        invalid_rows?: number
        status?: string
        error_report?: Json
        created_by?: string
        created_at?: string
        validated_at?: string
        completed_at?: string
      }
      Relationships: [
      ]
    }
    import_column_mappings: {
      Row: {
        id: string
        tenant_id: string
        name: string
        target_table: string
        mapping: Json
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        target_table: string
        mapping: Json
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        target_table?: string
        mapping?: Json
        created_at?: string
        updated_at?: string
      }
      Relationships: [
      ]
    }
    interview_campaigns: {
      Row: {
        id: string
        tenant_id: string
        name: string
        campaign_type: string
        start_date: string
        end_date: string | null
        reminder_days: number | null
        status: string | null
        form_template: Json | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        campaign_type: string
        start_date: string
        end_date?: string
        reminder_days?: number
        status?: string
        form_template?: Json
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        campaign_type?: string
        start_date?: string
        end_date?: string
        reminder_days?: number
        status?: string
        form_template?: Json
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "interview_campaigns_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    interviews: {
      Row: {
        id: string
        tenant_id: string
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
        form_data: Json | null
        employee_feedback: string | null
        employee_rating: number | null
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        type?: string
        scheduled_date?: string
        conducted_at?: string
        conducted_by?: string
        objectives?: string
        feedback?: string
        rating?: number
        status?: string
        created_at?: string
        campaign_id?: string
        form_data?: Json
        employee_feedback?: string
        employee_rating?: number
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        type?: string
        scheduled_date?: string
        conducted_at?: string
        conducted_by?: string
        objectives?: string
        feedback?: string
        rating?: number
        status?: string
        created_at?: string
        campaign_id?: string
        form_data?: Json
        employee_feedback?: string
        employee_rating?: number
      }
      Relationships: [
        {
          foreignKeyName: "interviews_campaign_id_fkey",
          columns: ["tenant_id", "campaign_id"],
          isOneToOne: false,
          referencedRelation: "interview_campaigns",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "interviews_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    intra_group_transactions: {
      Row: {
        id: string
        group_id: string
        from_tenant_id: string
        to_tenant_id: string
        transaction_type: string
        amount: number
        currency: string
        reference: string | null
        label: string | null
        transaction_date: string
        status: string
        created_by: string | null
        created_at: string
      }
      Insert: {
        id?: string
        group_id: string
        from_tenant_id: string
        to_tenant_id: string
        transaction_type: string
        amount: number
        currency?: string
        reference?: string
        label?: string
        transaction_date: string
        status?: string
        created_by?: string
        created_at?: string
      }
      Update: {
        id?: string
        group_id?: string
        from_tenant_id?: string
        to_tenant_id?: string
        transaction_type?: string
        amount?: number
        currency?: string
        reference?: string
        label?: string
        transaction_date?: string
        status?: string
        created_by?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "intra_group_transactions_from_tenant_id_fkey",
          columns: ["from_tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "intra_group_transactions_group_id_fkey",
          columns: ["group_id"],
          isOneToOne: true,
          referencedRelation: "groups",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "intra_group_transactions_to_tenant_id_fkey",
          columns: ["to_tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    investments: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        name: string
        type?: string
        institution?: string
        initial_amount?: number
        current_value?: number
        acquisition_date?: string
        maturity_date?: string
        interest_rate?: number
        status?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        type?: string
        institution?: string
        initial_amount?: number
        current_value?: number
        acquisition_date?: string
        maturity_date?: string
        interest_rate?: number
        status?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
      ]
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
        vat_code: string | null
        vat_amount: number | null
        advance_invoice_id: string | null
        time_entry_id: string | null
        analytic_section_id: string | null
        account_code: string | null
      }
      Insert: {
        id?: string
        invoice_id?: string
        product_id?: string
        description: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        total?: number
        vat_total?: number
        line_order?: number
        created_at?: string
        tenant_id: string
        delivery_note_line_id?: string
        sales_order_line_id?: string
        vat_code?: string
        vat_amount?: number
        advance_invoice_id?: string
        time_entry_id?: string
        analytic_section_id?: string
        account_code?: string
      }
      Update: {
        id?: string
        invoice_id?: string
        product_id?: string
        description?: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        total?: number
        vat_total?: number
        line_order?: number
        created_at?: string
        tenant_id?: string
        delivery_note_line_id?: string
        sales_order_line_id?: string
        vat_code?: string
        vat_amount?: number
        advance_invoice_id?: string
        time_entry_id?: string
        analytic_section_id?: string
        account_code?: string
      }
      Relationships: [
        {
          foreignKeyName: "invoice_lines_analytic_section_fk",
          columns: ["tenant_id", "analytic_section_id"],
          isOneToOne: false,
          referencedRelation: "analytic_sections",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "invoice_lines_delivery_note_line_id_fkey",
          columns: ["tenant_id", "delivery_note_line_id"],
          isOneToOne: false,
          referencedRelation: "delivery_note_lines",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "invoice_lines_invoice_id_fkey",
          columns: ["tenant_id", "invoice_id"],
          isOneToOne: false,
          referencedRelation: "invoices",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "invoice_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "invoice_lines_sales_order_line_id_fkey",
          columns: ["tenant_id", "sales_order_line_id"],
          isOneToOne: false,
          referencedRelation: "sales_order_lines",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "invoice_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "invoice_lines_time_entry_fk",
          columns: ["tenant_id", "time_entry_id"],
          isOneToOne: false,
          referencedRelation: "project_time_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
        project_id: string | null
        e_invoice_status: string | null
        e_invoice_platform: string | null
        e_invoice_submitted_at: string | null
        e_invoice_id: string | null
      }
      Insert: {
        id?: string
        number: string
        customer_id?: string
        customer_name?: string
        date?: string
        due_date: string
        status?: string
        subtotal?: number
        vat_total?: number
        total?: number
        amount_paid?: number
        amount_due?: number
        notes?: string
        recurring?: boolean
        recurring_frequency?: string
        created_at?: string
        updated_at?: string
        tenant_id: string
        validation_status?: string
        fiscal_position_id?: string
        payment_state?: string
        currency_code?: string
        exchange_rate?: number
        amount_untaxed_currency?: number
        amount_tax_currency?: number
        amount_total_currency?: number
        delivery_note_id?: string
        sales_order_id?: string
        quote_id?: string
        is_advance_invoice?: boolean
        advance_amount?: number
        invoice_type?: string
        parent_invoice_id?: string
        transferred_entry_id?: string
        project_id?: string
        e_invoice_status?: string
        e_invoice_platform?: string
        e_invoice_submitted_at?: string
        e_invoice_id?: string
      }
      Update: {
        id?: string
        number?: string
        customer_id?: string
        customer_name?: string
        date?: string
        due_date?: string
        status?: string
        subtotal?: number
        vat_total?: number
        total?: number
        amount_paid?: number
        amount_due?: number
        notes?: string
        recurring?: boolean
        recurring_frequency?: string
        created_at?: string
        updated_at?: string
        tenant_id?: string
        validation_status?: string
        fiscal_position_id?: string
        payment_state?: string
        currency_code?: string
        exchange_rate?: number
        amount_untaxed_currency?: number
        amount_tax_currency?: number
        amount_total_currency?: number
        delivery_note_id?: string
        sales_order_id?: string
        quote_id?: string
        is_advance_invoice?: boolean
        advance_amount?: number
        invoice_type?: string
        parent_invoice_id?: string
        transferred_entry_id?: string
        project_id?: string
        e_invoice_status?: string
        e_invoice_platform?: string
        e_invoice_submitted_at?: string
        e_invoice_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "invoices_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "invoices_delivery_note_id_fkey",
          columns: ["tenant_id", "delivery_note_id"],
          isOneToOne: false,
          referencedRelation: "delivery_notes",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "invoices_fiscal_position_id_fkey",
          columns: ["tenant_id", "fiscal_position_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_positions",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "invoices_parent_invoice_id_fkey",
          columns: ["tenant_id", "parent_invoice_id"],
          isOneToOne: false,
          referencedRelation: "invoices",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "invoices_project_fk",
          columns: ["tenant_id", "project_id"],
          isOneToOne: false,
          referencedRelation: "projects",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "invoices_quote_id_fkey",
          columns: ["tenant_id", "quote_id"],
          isOneToOne: false,
          referencedRelation: "quotes",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "invoices_sales_order_id_fkey",
          columns: ["tenant_id", "sales_order_id"],
          isOneToOne: false,
          referencedRelation: "sales_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "invoices_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "invoices_transferred_entry_id_fkey",
          columns: ["tenant_id", "transferred_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    journal_access_rights: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        user_id: string
        journal_code: string
        can_view?: boolean
        can_create?: boolean
        can_edit?: boolean
        can_delete?: boolean
        can_close?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        user_id?: string
        journal_code?: string
        can_view?: boolean
        can_create?: boolean
        can_edit?: boolean
        can_delete?: boolean
        can_close?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "journal_access_rights_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        journal_code: string
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
        created_by: string | null
        fiscal_year_id: string | null
        posting_seq: number | null
        posting_number: string | null
        is_manual: boolean
      }
      Insert: {
        id?: string
        number: string
        date?: string
        description: string
        reference?: string
        status?: string
        total_debit?: number
        total_credit?: number
        created_at?: string
        updated_at?: string
        journal_code: string
        fiscal_period_id?: string
        piece_number?: string
        invoice_ref?: string
        entry_template_id?: string
        status_detail?: string
        validated_by?: string
        validated_at?: string
        tenant_id: string
        ifrs_mode?: boolean
        currency_code?: string
        functional_currency?: string
        exchange_rate?: number
        exchange_rate_date?: string
        created_by?: string
        fiscal_year_id?: string
        posting_seq?: number
        posting_number?: string
        is_manual?: boolean
      }
      Update: {
        id?: string
        number?: string
        date?: string
        description?: string
        reference?: string
        status?: string
        total_debit?: number
        total_credit?: number
        created_at?: string
        updated_at?: string
        journal_code?: string
        fiscal_period_id?: string
        piece_number?: string
        invoice_ref?: string
        entry_template_id?: string
        status_detail?: string
        validated_by?: string
        validated_at?: string
        tenant_id?: string
        ifrs_mode?: boolean
        currency_code?: string
        functional_currency?: string
        exchange_rate?: number
        exchange_rate_date?: string
        created_by?: string
        fiscal_year_id?: string
        posting_seq?: number
        posting_number?: string
        is_manual?: boolean
      }
      Relationships: [
        {
          foreignKeyName: "journal_entries_entry_template_id_fkey",
          columns: ["tenant_id", "entry_template_id"],
          isOneToOne: false,
          referencedRelation: "entry_templates",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "journal_entries_fiscal_period_id_fkey",
          columns: ["tenant_id", "fiscal_period_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_periods",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "journal_entries_fiscal_year_id_fkey",
          columns: ["tenant_id", "fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "journal_entries_journal_fkey",
          columns: ["tenant_id", "journal_code"],
          isOneToOne: false,
          referencedRelation: "journals",
          referencedColumns: ["tenant_id", "code"]
        },
        {
          foreignKeyName: "journal_entries_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    journal_lines: {
      Row: {
        id: string
        journal_id: string | null
        account_code: string
        account_name: string | null
        debit: number
        credit: number
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
        tax_tag_ids: string[] | null
        analytic_distribution: Json | null
        amount_residual: number | null
        product_id: string | null
        product_uom: string | null
        lettrage_partial: boolean | null
        lettrage_group_id: string | null
        currency_code: string | null
        currency_amount: number | null
        exchange_rate: number | null
      }
      Insert: {
        id?: string
        journal_id?: string
        account_code: string
        account_name?: string
        debit?: number
        credit?: number
        description?: string
        line_order?: number
        created_at?: string
        account_general?: string
        account_tiers?: string
        third_party_id?: string
        lettrage_code?: string
        lettrage_date?: string
        piece_number?: string
        reference?: string
        analytic_section_id?: string
        analytic_amount?: number
        running_balance?: number
        reconciled?: boolean
        line_date?: string
        tenant_id: string
        vat_code?: string
        vat_amount?: number
        echeance_date?: string
        quantity?: number
        marking_code?: string
        marked_bap?: boolean
        marked_bap_date?: string
        tax_tag_ids?: string[]
        analytic_distribution?: Json
        amount_residual?: number
        product_id?: string
        product_uom?: string
        lettrage_partial?: boolean
        lettrage_group_id?: string
        currency_code?: string
        currency_amount?: number
        exchange_rate?: number
      }
      Update: {
        id?: string
        journal_id?: string
        account_code?: string
        account_name?: string
        debit?: number
        credit?: number
        description?: string
        line_order?: number
        created_at?: string
        account_general?: string
        account_tiers?: string
        third_party_id?: string
        lettrage_code?: string
        lettrage_date?: string
        piece_number?: string
        reference?: string
        analytic_section_id?: string
        analytic_amount?: number
        running_balance?: number
        reconciled?: boolean
        line_date?: string
        tenant_id?: string
        vat_code?: string
        vat_amount?: number
        echeance_date?: string
        quantity?: number
        marking_code?: string
        marked_bap?: boolean
        marked_bap_date?: string
        tax_tag_ids?: string[]
        analytic_distribution?: Json
        amount_residual?: number
        product_id?: string
        product_uom?: string
        lettrage_partial?: boolean
        lettrage_group_id?: string
        currency_code?: string
        currency_amount?: number
        exchange_rate?: number
      }
      Relationships: [
        {
          foreignKeyName: "journal_lines_analytic_section_id_fkey",
          columns: ["tenant_id", "analytic_section_id"],
          isOneToOne: false,
          referencedRelation: "analytic_sections",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "journal_lines_journal_id_fkey",
          columns: ["tenant_id", "journal_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "journal_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "journal_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    journal_posting_sequences: {
      Row: {
        tenant_id: string
        journal_code: string
        fiscal_year_id: string
        last_seq: number
      }
      Insert: {
        tenant_id: string
        journal_code: string
        fiscal_year_id: string
        last_seq?: number
      }
      Update: {
        tenant_id?: string
        journal_code?: string
        fiscal_year_id?: string
        last_seq?: number
      }
      Relationships: [
        {
          foreignKeyName: "journal_posting_sequences_fiscal_year_id_fkey",
          columns: ["tenant_id", "fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "journal_posting_sequences_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        racines_autorisees: string | null
      }
      Insert: {
        id?: string
        code: string
        name: string
        type: string
        account_counterpart?: string
        bank_account_id?: string
        default_entry_template_id?: string
        status?: string
        locked?: boolean
        created_at?: string
        updated_at?: string
        tenant_id: string
        access_level?: string
        numbering_mode?: string
        account_attente?: string
        is_analytic?: boolean
        analytic_plan_id?: string
        currency_code?: string
        sequence?: number
        next_number?: number
        racines_autorisees?: string
      }
      Update: {
        id?: string
        code?: string
        name?: string
        type?: string
        account_counterpart?: string
        bank_account_id?: string
        default_entry_template_id?: string
        status?: string
        locked?: boolean
        created_at?: string
        updated_at?: string
        tenant_id?: string
        access_level?: string
        numbering_mode?: string
        account_attente?: string
        is_analytic?: boolean
        analytic_plan_id?: string
        currency_code?: string
        sequence?: number
        next_number?: number
        racines_autorisees?: string
      }
      Relationships: [
        {
          foreignKeyName: "journals_bank_account_id_fkey",
          columns: ["tenant_id", "bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "journals_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    justificatif_solde: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        account_code: string
        third_party_code?: string
        fiscal_period_id?: string
        opening_balance?: number
        total_debit?: number
        total_credit?: number
        closing_balance?: number
        generated_at?: string
        generated_by?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        account_code?: string
        third_party_code?: string
        fiscal_period_id?: string
        opening_balance?: number
        total_debit?: number
        total_credit?: number
        closing_balance?: number
        generated_at?: string
        generated_by?: string
      }
      Relationships: [
        {
          foreignKeyName: "js_fiscal_period_id_fkey",
          columns: ["tenant_id", "fiscal_period_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_periods",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "justificatif_solde_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    knowledge_base_articles: {
      Row: {
        id: string
        tenant_id: string
        title: string
        category: string | null
        content: string
        tags: string[] | null
        author: string | null
        status: string | null
        views: number | null
        helpful_count: number | null
        not_helpful_count: number | null
        is_public: boolean | null
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        title: string
        category?: string
        content: string
        tags?: string[]
        author?: string
        status?: string
        views?: number
        helpful_count?: number
        not_helpful_count?: number
        is_public?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        title?: string
        category?: string
        content?: string
        tags?: string[]
        author?: string
        status?: string
        views?: number
        helpful_count?: number
        not_helpful_count?: number
        is_public?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "knowledge_base_articles_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    landed_cost_lines: {
      Row: {
        id: string
        tenant_id: string
        landed_cost_id: string
        receipt_id: string | null
        product_id: string | null
        distributed_amount: number
        original_unit_cost: number | null
        new_unit_cost: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        landed_cost_id: string
        receipt_id?: string
        product_id?: string
        distributed_amount: number
        original_unit_cost?: number
        new_unit_cost?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        landed_cost_id?: string
        receipt_id?: string
        product_id?: string
        distributed_amount?: number
        original_unit_cost?: number
        new_unit_cost?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "landed_cost_lines_landed_cost_id_fkey",
          columns: ["tenant_id", "landed_cost_id"],
          isOneToOne: false,
          referencedRelation: "landed_costs",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    landed_costs: {
      Row: {
        id: string
        tenant_id: string
        invoice_number: string | null
        supplier_id: string | null
        total_amount: number
        distribution_method: string
        status: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        invoice_number?: string
        supplier_id?: string
        total_amount: number
        distribution_method?: string
        status?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        invoice_number?: string
        supplier_id?: string
        total_amount?: number
        distribution_method?: string
        status?: string
        created_at?: string
      }
      Relationships: [
      ]
    }
    leave_balances: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        leave_type: string
        year?: number
        acquired?: number
        taken?: number
        pending?: number
        remaining?: number
        carry_over?: number
        provision?: number
        provision_calculated_at?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        leave_type?: string
        year?: number
        acquired?: number
        taken?: number
        pending?: number
        remaining?: number
        carry_over?: number
        provision?: number
        provision_calculated_at?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "leave_balances_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "leave_balances_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    leave_provisions: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        period: string
        cp_remaining_days?: number
        rtt_remaining_days?: number
        recovery_remaining_days?: number
        daily_rate?: number
        cp_provision?: number
        rtt_provision?: number
        recovery_provision?: number
        total_provision?: number
        accounting_entry_id?: string
        status?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        period?: string
        cp_remaining_days?: number
        rtt_remaining_days?: number
        recovery_remaining_days?: number
        daily_rate?: number
        cp_provision?: number
        rtt_provision?: number
        recovery_provision?: number
        total_provision?: number
        accounting_entry_id?: string
        status?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "leave_provisions_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "leave_provisions_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "lp_accounting_entry_id_fkey",
          columns: ["tenant_id", "accounting_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
        manager_comment: string | null
      }
      Insert: {
        id?: string
        employee_id: string
        leave_type: string
        start_date: string
        end_date: string
        days?: number
        status?: string
        reason?: string
        approved_by?: string
        approved_at?: string
        created_at?: string
        tenant_id: string
        manager_comment?: string
      }
      Update: {
        id?: string
        employee_id?: string
        leave_type?: string
        start_date?: string
        end_date?: string
        days?: number
        status?: string
        reason?: string
        approved_by?: string
        approved_at?: string
        created_at?: string
        tenant_id?: string
        manager_comment?: string
      }
      Relationships: [
        {
          foreignKeyName: "leave_requests_approved_by_fkey",
          columns: ["tenant_id", "approved_by"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "leave_requests_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "leave_requests_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        lateness_threshold_minutes: number | null
        lateness_deduction_rate: number | null
        lateness_grace_period: number | null
      }
      Insert: {
        id?: string
        tenant_id?: string
        leave_type: string
        label: string
        accrual_rate?: number
        max_carry_over?: number
        carry_over_expiry_months?: number
        requires_justification?: boolean
        requires_manager_approval?: boolean
        min_notice_days?: number
        max_consecutive_days?: number
        color?: string
        count_method?: string
        affects_pay?: boolean
        deduction_rate?: number
        active?: boolean
        created_at?: string
        lateness_threshold_minutes?: number
        lateness_deduction_rate?: number
        lateness_grace_period?: number
      }
      Update: {
        id?: string
        tenant_id?: string
        leave_type?: string
        label?: string
        accrual_rate?: number
        max_carry_over?: number
        carry_over_expiry_months?: number
        requires_justification?: boolean
        requires_manager_approval?: boolean
        min_notice_days?: number
        max_consecutive_days?: number
        color?: string
        count_method?: string
        affects_pay?: boolean
        deduction_rate?: number
        active?: boolean
        created_at?: string
        lateness_threshold_minutes?: number
        lateness_deduction_rate?: number
        lateness_grace_period?: number
      }
      Relationships: [
        {
          foreignKeyName: "leave_rules_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: false,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        number: string
        declaration_type: string
        period_month: number
        period_year: number
        due_date: string
        submission_date?: string
        amount?: number
        status?: string
        notes?: string
        created_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        number?: string
        declaration_type?: string
        period_month?: number
        period_year?: number
        due_date?: string
        submission_date?: string
        amount?: number
        status?: string
        notes?: string
        created_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "legal_declarations_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    legal_watch: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        title: string
        category?: string
        source?: string
        summary?: string
        content_url?: string
        published_date?: string
        relevance?: string
        read?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        title?: string
        category?: string
        source?: string
        summary?: string
        content_url?: string
        published_date?: string
        relevance?: string
        read?: boolean
        created_at?: string
      }
      Relationships: [
      ]
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
        tenant_id: string
      }
      Insert: {
        code: string
        name: string
        country_code: string
        country_name: string
        accounting_standard: string
        currency?: string
        currency_decimals?: number
        date_format?: string
        locale?: string
        fiscal_year_start?: string
        tax_id_label?: string
        tax_id_secondary_label?: string
        is_default?: boolean
        active?: boolean
        created_at?: string
        updated_at?: string
        tenant_id: string
      }
      Update: {
        code?: string
        name?: string
        country_code?: string
        country_name?: string
        accounting_standard?: string
        currency?: string
        currency_decimals?: number
        date_format?: string
        locale?: string
        fiscal_year_start?: string
        tax_id_label?: string
        tax_id_secondary_label?: string
        is_default?: boolean
        active?: boolean
        created_at?: string
        updated_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "legislation_packs_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    lettrage_differences: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        third_party_code: string
        lettrage_code: string
        line_id_1: string
        line_id_2: string
        debit_amount?: number
        credit_amount?: number
        difference?: number
        difference_account?: string
        generated_entry_id?: string
        status?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        third_party_code?: string
        lettrage_code?: string
        line_id_1?: string
        line_id_2?: string
        debit_amount?: number
        credit_amount?: number
        difference?: number
        difference_account?: string
        generated_entry_id?: string
        status?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "ld_generated_entry_id_fkey",
          columns: ["tenant_id", "generated_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "lettrage_differences_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    lettrage_groups: {
      Row: {
        id: string
        tenant_id: string
        lettrage_code: string
        lettrage_date: string
        total_debit: number | null
        total_credit: number | null
        residual_amount: number | null
        residual_type: string | null
        status: string | null
        created_by: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        lettrage_code: string
        lettrage_date?: string
        total_debit?: number
        total_credit?: number
        residual_amount?: number
        residual_type?: string
        status?: string
        created_by?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        lettrage_code?: string
        lettrage_date?: string
        total_debit?: number
        total_credit?: number
        residual_amount?: number
        residual_type?: string
        status?: string
        created_by?: string
        created_at?: string
      }
      Relationships: [
      ]
    }
    machines: {
      Row: {
        id: string
        tenant_id: string
        code: string
        name: string
        work_center_id: string | null
        capacity_per_hour: number | null
        status: string | null
        purchase_date: string | null
        notes: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        code: string
        name: string
        work_center_id?: string
        capacity_per_hour?: number
        status?: string
        purchase_date?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        name?: string
        work_center_id?: string
        capacity_per_hour?: number
        status?: string
        purchase_date?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "machines_work_center_id_fkey",
          columns: ["tenant_id", "work_center_id"],
          isOneToOne: false,
          referencedRelation: "work_centers",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    maintenance_plans: {
      Row: {
        id: string
        tenant_id: string
        machine_id: string | null
        tool_id: string | null
        name: string
        maintenance_type: string
        frequency_days: number | null
        last_maintenance_date: string | null
        next_maintenance_date: string | null
        is_active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        machine_id?: string
        tool_id?: string
        name: string
        maintenance_type: string
        frequency_days?: number
        last_maintenance_date?: string
        next_maintenance_date?: string
        is_active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        machine_id?: string
        tool_id?: string
        name?: string
        maintenance_type?: string
        frequency_days?: number
        last_maintenance_date?: string
        next_maintenance_date?: string
        is_active?: boolean
        created_at?: string
      }
      Relationships: [
      ]
    }
    maintenance_records: {
      Row: {
        id: string
        tenant_id: string
        plan_id: string | null
        machine_id: string | null
        tool_id: string | null
        maintenance_date: string
        duration_hours: number | null
        cost: number | null
        technician: string | null
        notes: string | null
        status: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        plan_id?: string
        machine_id?: string
        tool_id?: string
        maintenance_date: string
        duration_hours?: number
        cost?: number
        technician?: string
        notes?: string
        status?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        plan_id?: string
        machine_id?: string
        tool_id?: string
        maintenance_date?: string
        duration_hours?: number
        cost?: number
        technician?: string
        notes?: string
        status?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "maintenance_records_plan_id_fkey",
          columns: ["tenant_id", "plan_id"],
          isOneToOne: false,
          referencedRelation: "maintenance_plans",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
        cost_material: number | null
        cost_labor: number | null
        cost_overhead: number | null
        cost_total: number | null
        unit_cost: number | null
        qty_produced: number | null
        qty_scrapped: number | null
        cost_variance: number | null
      }
      Insert: {
        id?: string
        number: string
        bom_id?: string
        product_id?: string
        quantity?: number
        status?: string
        start_date?: string
        end_date?: string
        warehouse_id?: string
        notes?: string
        created_at?: string
        tenant_id: string
        routing_id?: string
        origin?: string
        parent_mo_id?: string
        lot_number?: string
        expiry_date?: string
        custom_expiry_date?: string
        expiry_type?: string
        label_enabled?: boolean
        additional_text?: string
        cost_material?: number
        cost_labor?: number
        cost_overhead?: number
        cost_total?: number
        unit_cost?: number
        qty_produced?: number
        qty_scrapped?: number
        cost_variance?: number
      }
      Update: {
        id?: string
        number?: string
        bom_id?: string
        product_id?: string
        quantity?: number
        status?: string
        start_date?: string
        end_date?: string
        warehouse_id?: string
        notes?: string
        created_at?: string
        tenant_id?: string
        routing_id?: string
        origin?: string
        parent_mo_id?: string
        lot_number?: string
        expiry_date?: string
        custom_expiry_date?: string
        expiry_type?: string
        label_enabled?: boolean
        additional_text?: string
        cost_material?: number
        cost_labor?: number
        cost_overhead?: number
        cost_total?: number
        unit_cost?: number
        qty_produced?: number
        qty_scrapped?: number
        cost_variance?: number
      }
      Relationships: [
        {
          foreignKeyName: "manufacturing_orders_bom_id_fkey",
          columns: ["tenant_id", "bom_id"],
          isOneToOne: false,
          referencedRelation: "boms",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "manufacturing_orders_parent_mo_id_fkey",
          columns: ["tenant_id", "parent_mo_id"],
          isOneToOne: false,
          referencedRelation: "manufacturing_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "manufacturing_orders_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "manufacturing_orders_routing_id_fkey",
          columns: ["tenant_id", "routing_id"],
          isOneToOne: false,
          referencedRelation: "routings",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "manufacturing_orders_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "manufacturing_orders_warehouse_id_fkey",
          columns: ["tenant_id", "warehouse_id"],
          isOneToOne: false,
          referencedRelation: "warehouses",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    marking_types: {
      Row: {
        id: string
        tenant_id: string
        code: string
        label: string
        color: string | null
        active: boolean | null
        created_at: string
        updated_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        code: string
        label: string
        color?: string
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        label?: string
        color?: string
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "marking_types_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    meal_voucher_config: {
      Row: {
        id: string
        tenant_id: string | null
        voucher_value: number
        employer_share: number | null
        employee_share: number | null
        eligible_days: string[] | null
        max_per_month: number | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id?: string
        voucher_value?: number
        employer_share?: number
        employee_share?: number
        eligible_days?: string[]
        max_per_month?: number
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        voucher_value?: number
        employer_share?: number
        employee_share?: number
        eligible_days?: string[]
        max_per_month?: number
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "meal_voucher_config_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: false,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    medical_exams: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        exam_type: string
        scheduled_date: string
        completed_date?: string
        result?: string
        restrictions?: string
        next_exam_date?: string
        occupational_doctor?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        exam_type?: string
        scheduled_date?: string
        completed_date?: string
        result?: string
        restrictions?: string
        next_exam_date?: string
        occupational_doctor?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "medical_exams_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "medical_exams_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    metric_definitions: {
      Row: {
        id: string
        tenant_id: string | null
        code: string
        version: number
        libelle: string
        unite: string | null
        sql_definition: string
        valide_du: string
        valide_au: string | null
        note: string | null
        cree_le: string
      }
      Insert: {
        id?: string
        tenant_id?: string
        code: string
        version: number
        libelle: string
        unite?: string
        sql_definition: string
        valide_du: string
        valide_au?: string
        note?: string
        cree_le?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        version?: number
        libelle?: string
        unite?: string
        sql_definition?: string
        valide_du?: string
        valide_au?: string
        note?: string
        cree_le?: string
      }
      Relationships: [
        {
          foreignKeyName: "metric_definitions_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: false,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        config: Json | null
        install_status: string | null
        verification_data: Json | null
        verified_at: string | null
        install_token: string | null
        install_platform: string | null
        tenant_id: string
      }
      Insert: {
        id?: string
        machine_id: string
        machine_name: string
        os?: string
        ip_address?: string
        mirror_dir?: string
        registered_at?: string
        last_heartbeat?: string
        status?: string
        config?: Json
        install_status?: string
        verification_data?: Json
        verified_at?: string
        install_token?: string
        install_platform?: string
        tenant_id: string
      }
      Update: {
        id?: string
        machine_id?: string
        machine_name?: string
        os?: string
        ip_address?: string
        mirror_dir?: string
        registered_at?: string
        last_heartbeat?: string
        status?: string
        config?: Json
        install_status?: string
        verification_data?: Json
        verified_at?: string
        install_token?: string
        install_platform?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "mirror_servers_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        mirror_server_id?: string
        table_name: string
        cloud_rows?: number
        local_rows?: number
        match?: boolean
        verified_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        mirror_server_id?: string
        table_name?: string
        cloud_rows?: number
        local_rows?: number
        match?: boolean
        verified_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "mirror_verification_details_mirror_server_id_fkey",
          columns: ["tenant_id", "mirror_server_id"],
          isOneToOne: false,
          referencedRelation: "mirror_servers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "mirror_verification_details_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    mo_consumptions: {
      Row: {
        id: string
        tenant_id: string
        manufacturing_order_id: string
        product_id: string
        theoretical_quantity: number
        actual_quantity: number | null
        lot_id: string | null
        variance_quantity: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        manufacturing_order_id: string
        product_id: string
        theoretical_quantity: number
        actual_quantity?: number
        lot_id?: string
        variance_quantity?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        manufacturing_order_id?: string
        product_id?: string
        theoretical_quantity?: number
        actual_quantity?: number
        lot_id?: string
        variance_quantity?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "mo_consumptions_manufacturing_order_id_fkey",
          columns: ["tenant_id", "manufacturing_order_id"],
          isOneToOne: false,
          referencedRelation: "manufacturing_orders",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    mo_operations: {
      Row: {
        id: string
        tenant_id: string
        manufacturing_order_id: string
        operation_id: string | null
        operation_name: string | null
        planned_time_minutes: number | null
        actual_time_minutes: number | null
        operator_id: string | null
        quantity_produced: number | null
        quantity_scrapped: number | null
        scrap_reason: string | null
        started_at: string | null
        completed_at: string | null
        status: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        manufacturing_order_id: string
        operation_id?: string
        operation_name?: string
        planned_time_minutes?: number
        actual_time_minutes?: number
        operator_id?: string
        quantity_produced?: number
        quantity_scrapped?: number
        scrap_reason?: string
        started_at?: string
        completed_at?: string
        status?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        manufacturing_order_id?: string
        operation_id?: string
        operation_name?: string
        planned_time_minutes?: number
        actual_time_minutes?: number
        operator_id?: string
        quantity_produced?: number
        quantity_scrapped?: number
        scrap_reason?: string
        started_at?: string
        completed_at?: string
        status?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "mo_operations_manufacturing_order_id_fkey",
          columns: ["tenant_id", "manufacturing_order_id"],
          isOneToOne: false,
          referencedRelation: "manufacturing_orders",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id: string
        document_id: string
        user_id: string
        action: string
        ip_address?: string
        user_agent?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        document_id?: string
        user_id?: string
        action?: string
        ip_address?: string
        user_agent?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "module_document_access_log_document_id_fkey",
          columns: ["tenant_id", "document_id"],
          isOneToOne: false,
          referencedRelation: "module_documents",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "module_document_access_log_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "module_document_access_log_user_id_fkey",
          columns: ["tenant_id", "user_id"],
          isOneToOne: false,
          referencedRelation: "tenant_users",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id: string
        document_id: string
        share_token: string
        password_hash?: string
        created_by: string
        expires_at?: string
        max_downloads?: number
        download_count?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        document_id?: string
        share_token?: string
        password_hash?: string
        created_by?: string
        expires_at?: string
        max_downloads?: number
        download_count?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "module_document_shares_created_by_fkey",
          columns: ["tenant_id", "created_by"],
          isOneToOne: false,
          referencedRelation: "tenant_users",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "module_document_shares_document_id_fkey",
          columns: ["tenant_id", "document_id"],
          isOneToOne: false,
          referencedRelation: "module_documents",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "module_document_shares_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        file_size: number | null
        mime_type: string | null
        file_hash: string | null
        status: string
        approved_by: string | null
        approved_at: string | null
        rejection_reason: string | null
        expires_at: string | null
        archived_at: string | null
        uploaded_by: string
        metadata: Json | null
        download_count: number | null
        created_at: string
        updated_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        module: string
        document_type: string
        confidentiality?: string
        entity_type?: string
        entity_id?: string
        title: string
        description?: string
        file_url: string
        file_name: string
        file_size?: number
        mime_type?: string
        file_hash?: string
        status?: string
        approved_by?: string
        approved_at?: string
        rejection_reason?: string
        expires_at?: string
        archived_at?: string
        uploaded_by: string
        metadata?: Json
        download_count?: number
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        module?: string
        document_type?: string
        confidentiality?: string
        entity_type?: string
        entity_id?: string
        title?: string
        description?: string
        file_url?: string
        file_name?: string
        file_size?: number
        mime_type?: string
        file_hash?: string
        status?: string
        approved_by?: string
        approved_at?: string
        rejection_reason?: string
        expires_at?: string
        archived_at?: string
        uploaded_by?: string
        metadata?: Json
        download_count?: number
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "module_documents_approved_by_fkey",
          columns: ["tenant_id", "approved_by"],
          isOneToOne: false,
          referencedRelation: "tenant_users",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "module_documents_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "module_documents_uploaded_by_fkey",
          columns: ["tenant_id", "uploaded_by"],
          isOneToOne: false,
          referencedRelation: "tenant_users",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    mrp_pending_docs: {
      Row: {
        id: string
        tenant_id: string
        doc_type: string
        doc_id: string | null
        product_id: string | null
        quantity: number | null
        status: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        doc_type: string
        doc_id?: string
        product_id?: string
        quantity?: number
        status?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        doc_type?: string
        doc_id?: string
        product_id?: string
        quantity?: number
        status?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "mrp_pending_docs_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    mrp_proposals: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        mrp_run_id: string
        product_id: string
        proposal_type?: string
        gross_need?: number
        stock_available?: number
        open_orders?: number
        net_need?: number
        suggested_quantity?: number
        suggested_date?: string
        bom_id?: string
        supplier_id?: string
        status?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        mrp_run_id?: string
        product_id?: string
        proposal_type?: string
        gross_need?: number
        stock_available?: number
        open_orders?: number
        net_need?: number
        suggested_quantity?: number
        suggested_date?: string
        bom_id?: string
        supplier_id?: string
        status?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "mrp_proposals_bom_id_fkey",
          columns: ["tenant_id", "bom_id"],
          isOneToOne: false,
          referencedRelation: "boms",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "mrp_proposals_mrp_run_id_fkey",
          columns: ["tenant_id", "mrp_run_id"],
          isOneToOne: false,
          referencedRelation: "mrp_runs",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "mrp_proposals_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "mrp_proposals_supplier_id_fkey",
          columns: ["tenant_id", "supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    mrp_runs: {
      Row: {
        id: string
        tenant_id: string
        run_number: string
        run_date: string | null
        status: string | null
        parameters: Json | null
        summary: Json | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        run_number: string
        run_date?: string
        status?: string
        parameters?: Json
        summary?: Json
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        run_number?: string
        run_date?: string
        status?: string
        parameters?: Json
        summary?: Json
        created_at?: string
      }
      Relationships: [
      ]
    }
    nf525_event_log: {
      Row: {
        id: number
        tenant_id: string
        event_type: string
        entity_type: string
        entity_id: string | null
        event_date: string
        user_id: string | null
        user_name: string | null
        event_data: Json | null
        previous_hash: string | null
        current_hash: string | null
        fiscal_year_code: string | null
        period: string | null
        closed: boolean | null
        created_at: string
      }
      Insert: {
        id?: number
        tenant_id: string
        event_type: string
        entity_type: string
        entity_id?: string
        event_date?: string
        user_id?: string
        user_name?: string
        event_data?: Json
        previous_hash?: string
        current_hash?: string
        fiscal_year_code?: string
        period?: string
        closed?: boolean
        created_at?: string
      }
      Update: {
        id?: number
        tenant_id?: string
        event_type?: string
        entity_type?: string
        entity_id?: string
        event_date?: string
        user_id?: string
        user_name?: string
        event_data?: Json
        previous_hash?: string
        current_hash?: string
        fiscal_year_code?: string
        period?: string
        closed?: boolean
        created_at?: string
      }
      Relationships: [
      ]
    }
    nf525_period_closures: {
      Row: {
        id: string
        tenant_id: string
        period: string
        event_count: number
        closing_hash: string
        closed_by: string | null
        closed_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        period: string
        event_count: number
        closing_hash: string
        closed_by?: string
        closed_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        period?: string
        event_count?: number
        closing_hash?: string
        closed_by?: string
        closed_at?: string
      }
      Relationships: [
      ]
    }
    notification_email_queue: {
      Row: {
        id: string
        tenant_id: string
        recipient_email: string
        recipient_name: string | null
        notification_type: string
        subject: string
        status: string | null
        resend_id: string | null
        error_message: string | null
        sent_at: string | null
        created_at: string | null
        metadata: Json | null
      }
      Insert: {
        id?: string
        tenant_id: string
        recipient_email: string
        recipient_name?: string
        notification_type: string
        subject: string
        status?: string
        resend_id?: string
        error_message?: string
        sent_at?: string
        created_at?: string
        metadata?: Json
      }
      Update: {
        id?: string
        tenant_id?: string
        recipient_email?: string
        recipient_name?: string
        notification_type?: string
        subject?: string
        status?: string
        resend_id?: string
        error_message?: string
        sent_at?: string
        created_at?: string
        metadata?: Json
      }
      Relationships: [
        {
          foreignKeyName: "notification_email_queue_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    notification_preferences: {
      Row: {
        id: string
        tenant_id: string
        employee_id: string
        email_enabled: boolean | null
        email_types: Json | null
        digest_mode: string | null
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        email_enabled?: boolean
        email_types?: Json
        digest_mode?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        email_enabled?: boolean
        email_types?: Json
        digest_mode?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "notification_preferences_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "notification_preferences_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    notifications: {
      Row: {
        id: string
        tenant_id: string
        user_id: string | null
        category: string
        severity: string
        title: string
        message: string
        link: string | null
        metadata: Json
        read_at: string | null
        created_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        user_id?: string
        category: string
        severity?: string
        title: string
        message: string
        link?: string
        metadata?: Json
        read_at?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        user_id?: string
        category?: string
        severity?: string
        title?: string
        message?: string
        link?: string
        metadata?: Json
        read_at?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "notifications_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    of_consumptions: {
      Row: {
        id: string
        tenant_id: string
        manufacturing_order_id: string
        product_id: string
        quantity: number
        unit: string | null
        consumption_date: string
        is_deferred: boolean | null
        notes: string | null
        created_at: string | null
        lot_id: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        manufacturing_order_id: string
        product_id: string
        quantity?: number
        unit?: string
        consumption_date?: string
        is_deferred?: boolean
        notes?: string
        created_at?: string
        lot_id?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        manufacturing_order_id?: string
        product_id?: string
        quantity?: number
        unit?: string
        consumption_date?: string
        is_deferred?: boolean
        notes?: string
        created_at?: string
        lot_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "of_consumptions_manufacturing_order_id_fkey",
          columns: ["tenant_id", "manufacturing_order_id"],
          isOneToOne: false,
          referencedRelation: "manufacturing_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "of_consumptions_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    of_document_access: {
      Row: {
        id: string
        tenant_id: string
        user_id: string
        document_type: string
        can_view: boolean | null
        can_print: boolean | null
        can_export: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        user_id: string
        document_type: string
        can_view?: boolean
        can_print?: boolean
        can_export?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        user_id?: string
        document_type?: string
        can_view?: boolean
        can_print?: boolean
        can_export?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "of_document_access_user_id_fkey",
          columns: ["tenant_id", "user_id"],
          isOneToOne: false,
          referencedRelation: "users",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    of_labels: {
      Row: {
        id: string
        tenant_id: string
        manufacturing_order_id: string
        label_number: string
        product_id: string | null
        planned_quantity: number | null
        actual_quantity: number | null
        is_complete: boolean | null
        is_declared: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        manufacturing_order_id: string
        label_number: string
        product_id?: string
        planned_quantity?: number
        actual_quantity?: number
        is_complete?: boolean
        is_declared?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        manufacturing_order_id?: string
        label_number?: string
        product_id?: string
        planned_quantity?: number
        actual_quantity?: number
        is_complete?: boolean
        is_declared?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "of_labels_manufacturing_order_id_fkey",
          columns: ["tenant_id", "manufacturing_order_id"],
          isOneToOne: false,
          referencedRelation: "manufacturing_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "of_labels_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    of_lots: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        manufacturing_order_id: string
        lot_number: string
        product_id?: string
        quantity?: number
        production_date?: string
        expiry_date?: string
        custom_expiry_date?: string
        expiry_type?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        manufacturing_order_id?: string
        lot_number?: string
        product_id?: string
        quantity?: number
        production_date?: string
        expiry_date?: string
        custom_expiry_date?: string
        expiry_type?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "of_lots_manufacturing_order_id_fkey",
          columns: ["tenant_id", "manufacturing_order_id"],
          isOneToOne: false,
          referencedRelation: "manufacturing_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "of_lots_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    online_payments: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        invoice_id?: string
        customer_id?: string
        payment_provider?: string
        provider_transaction_id?: string
        amount: number
        currency_code?: string
        status?: string
        payment_url?: string
        paid_at?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        invoice_id?: string
        customer_id?: string
        payment_provider?: string
        provider_transaction_id?: string
        amount?: number
        currency_code?: string
        status?: string
        payment_url?: string
        paid_at?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "online_payments_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "online_payments_invoice_id_fkey",
          columns: ["tenant_id", "invoice_id"],
          isOneToOne: false,
          referencedRelation: "invoices",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "online_payments_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    overtime_tiers: {
      Row: {
        id: string
        tenant_id: string
        from_hour: number
        to_hour: number | null
        rate_multiplier: number
        is_conventional: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        from_hour: number
        to_hour?: number
        rate_multiplier?: number
        is_conventional?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        from_hour?: number
        to_hour?: number
        rate_multiplier?: number
        is_conventional?: boolean
        created_at?: string
      }
      Relationships: [
      ]
    }
    partner_bank_accounts: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        partner_type: string
        partner_id: string
        account_number: string
        bank_name?: string
        bic?: string
        bank_code?: string
        sort_code?: string
        account_key?: string
        currency_code?: string
        is_default?: boolean
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        partner_type?: string
        partner_id?: string
        account_number?: string
        bank_name?: string
        bic?: string
        bank_code?: string
        sort_code?: string
        account_key?: string
        currency_code?: string
        is_default?: boolean
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "partner_bank_accounts_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    partner_categories: {
      Row: {
        id: string
        tenant_id: string
        name: string
        color: string | null
        parent_id: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        color?: string
        parent_id?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        color?: string
        parent_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "partner_categories_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "pc_parent_id_fkey",
          columns: ["tenant_id", "parent_id"],
          isOneToOne: false,
          referencedRelation: "partner_categories",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    partner_category_mappings: {
      Row: {
        id: string
        tenant_id: string
        category_id: string
        partner_type: string
        partner_id: string
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        category_id: string
        partner_type: string
        partner_id: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        category_id?: string
        partner_type?: string
        partner_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "partner_category_mappings_category_id_fkey",
          columns: ["tenant_id", "category_id"],
          isOneToOne: false,
          referencedRelation: "partner_categories",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "partner_category_mappings_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    partner_contacts: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        partner_type: string
        partner_id: string
        contact_type: string
        name: string
        email?: string
        phone?: string
        mobile?: string
        function?: string
        address?: string
        postal_code?: string
        city?: string
        country?: string
        is_default?: boolean
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        partner_type?: string
        partner_id?: string
        contact_type?: string
        name?: string
        email?: string
        phone?: string
        mobile?: string
        function?: string
        address?: string
        postal_code?: string
        city?: string
        country?: string
        is_default?: boolean
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "partner_contacts_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    pas_rates: {
      Row: {
        id: string
        tenant_id: string
        employee_id: string
        rate: number
        effective_date: string
        expiry_date: string | null
        source: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        rate?: number
        effective_date: string
        expiry_date?: string
        source?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        rate?: number
        effective_date?: string
        expiry_date?: string
        source?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "pas_rates_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "pas_rates_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    pay_recalls: {
      Row: {
        id: string
        tenant_id: string
        employee_id: string
        reference_period: string
        recall_amount: number
        reason: string | null
        status: string | null
        processed_pay_run_id: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        reference_period: string
        recall_amount?: number
        reason?: string
        status?: string
        processed_pay_run_id?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        reference_period?: string
        recall_amount?: number
        reason?: string
        status?: string
        processed_pay_run_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "pay_recalls_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "pay_recalls_processed_pay_run_id_fkey",
          columns: ["tenant_id", "processed_pay_run_id"],
          isOneToOne: false,
          referencedRelation: "pay_runs",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
      Insert: {
        id?: string
        number: string
        period_start: string
        period_end: string
        pay_date: string
        status?: string
        gross_total?: number
        tax_total?: number
        net_total?: number
        employee_count?: number
        created_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        number?: string
        period_start?: string
        period_end?: string
        pay_date?: string
        status?: string
        gross_total?: number
        tax_total?: number
        net_total?: number
        employee_count?: number
        created_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "pay_runs_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    pay_slip_clarified: {
      Row: {
        id: string
        tenant_id: string
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
        lines: Json | null
        created_at: string | null
        risk_group: string | null
        exemption_amount: number | null
        net_social: number | null
        net_imposable: number | null
        net_paid: number | null
      }
      Insert: {
        id?: string
        tenant_id: string
        pay_slip_id: string
        employee_id: string
        period: string
        gross_salary?: number
        social_charges_employee?: number
        social_charges_employer?: number
        income_tax?: number
        net_before_tax?: number
        net_after_tax?: number
        total_deductions?: number
        lines?: Json
        created_at?: string
        risk_group?: string
        exemption_amount?: number
        net_social?: number
        net_imposable?: number
        net_paid?: number
      }
      Update: {
        id?: string
        tenant_id?: string
        pay_slip_id?: string
        employee_id?: string
        period?: string
        gross_salary?: number
        social_charges_employee?: number
        social_charges_employer?: number
        income_tax?: number
        net_before_tax?: number
        net_after_tax?: number
        total_deductions?: number
        lines?: Json
        created_at?: string
        risk_group?: string
        exemption_amount?: number
        net_social?: number
        net_imposable?: number
        net_paid?: number
      }
      Relationships: [
        {
          foreignKeyName: "pay_slip_clarified_pay_slip_id_fkey",
          columns: ["tenant_id", "pay_slip_id"],
          isOneToOne: false,
          referencedRelation: "pay_slips",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "pay_slip_clarified_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        calc_inputs: Json | null
        journal_entry_id: string | null
        journal_posted: boolean | null
      }
      Insert: {
        id?: string
        number: string
        pay_run_id?: string
        employee_id: string
        period_start: string
        period_end: string
        gross_salary?: number
        overtime_pay?: number
        bonus?: number
        total_gross?: number
        social_security_employee?: number
        income_tax?: number
        other_deductions?: number
        total_deductions?: number
        net_salary?: number
        employer_contributions?: number
        status?: string
        payment_date?: string
        created_at?: string
        tenant_id: string
        calc_inputs?: Json
        journal_entry_id?: string
        journal_posted?: boolean
      }
      Update: {
        id?: string
        number?: string
        pay_run_id?: string
        employee_id?: string
        period_start?: string
        period_end?: string
        gross_salary?: number
        overtime_pay?: number
        bonus?: number
        total_gross?: number
        social_security_employee?: number
        income_tax?: number
        other_deductions?: number
        total_deductions?: number
        net_salary?: number
        employer_contributions?: number
        status?: string
        payment_date?: string
        created_at?: string
        tenant_id?: string
        calc_inputs?: Json
        journal_entry_id?: string
        journal_posted?: boolean
      }
      Relationships: [
        {
          foreignKeyName: "pay_slips_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "pay_slips_pay_run_id_fkey",
          columns: ["tenant_id", "pay_run_id"],
          isOneToOne: false,
          referencedRelation: "pay_runs",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "pay_slips_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        number: string
        type: string
        status?: string
        bank_account_id?: string
        third_party_id?: string
        third_party_name?: string
        third_party_iban?: string
        amount?: number
        payment_date?: string
        reference?: string
        description?: string
        remise_number?: string
        created_at?: string
        updated_at?: string
        tenant_id: string
        currency_code?: string
        exchange_rate?: number
        amount_currency?: number
        exchange_gain_loss?: number
      }
      Update: {
        id?: string
        number?: string
        type?: string
        status?: string
        bank_account_id?: string
        third_party_id?: string
        third_party_name?: string
        third_party_iban?: string
        amount?: number
        payment_date?: string
        reference?: string
        description?: string
        remise_number?: string
        created_at?: string
        updated_at?: string
        tenant_id?: string
        currency_code?: string
        exchange_rate?: number
        amount_currency?: number
        exchange_gain_loss?: number
      }
      Relationships: [
        {
          foreignKeyName: "payment_orders_bank_account_id_fkey",
          columns: ["tenant_id", "bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "payment_orders_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "payment_orders_third_party_id_fkey",
          columns: ["tenant_id", "third_party_id"],
          isOneToOne: false,
          referencedRelation: "third_party_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    payment_promises: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        third_party_code: string
        amount?: number
        promised_date: string
        reminder_level?: number
        status?: string
        notes?: string
        created_by?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        third_party_code?: string
        amount?: number
        promised_date?: string
        reminder_level?: number
        status?: string
        notes?: string
        created_by?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "payment_promises_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    payment_templates_compta: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        code: string
        name: string
        description?: string
        payment_method?: string
        day_count?: number
        end_of_month?: boolean
        is_active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        name?: string
        description?: string
        payment_method?: string
        day_count?: number
        end_of_month?: boolean
        is_active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "payment_templates_compta_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    payment_terms: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        code: string
        name: string
        type: string
        days_1?: number
        days_2?: number
        pct_1?: number
        pct_2?: number
        end_of_month?: boolean
        description?: string
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        name?: string
        type?: string
        days_1?: number
        days_2?: number
        pct_1?: number
        pct_2?: number
        end_of_month?: boolean
        description?: string
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "payment_terms_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    payroll_account_mapping: {
      Row: {
        id: string
        tenant_id: string | null
        role: string
        account_code: string
        created_at: string
      }
      Insert: {
        id?: string
        tenant_id?: string
        role: string
        account_code: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        role?: string
        account_code?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "payroll_account_mapping_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: false,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        number: string
        pay_run_id?: string
        period_date: string
        gross_total?: number
        employer_contributions_total?: number
        employee_deductions_total?: number
        net_total?: number
        journal_entry_id?: string
        status?: string
        created_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        number?: string
        pay_run_id?: string
        period_date?: string
        gross_total?: number
        employer_contributions_total?: number
        employee_deductions_total?: number
        net_total?: number
        journal_entry_id?: string
        status?: string
        created_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "payroll_accounting_entries_journal_entry_id_fkey",
          columns: ["tenant_id", "journal_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "payroll_accounting_entries_pay_run_id_fkey",
          columns: ["tenant_id", "pay_run_id"],
          isOneToOne: false,
          referencedRelation: "pay_runs",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "payroll_accounting_entries_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    payroll_archives: {
      Row: {
        id: string
        tenant_id: string
        employee_id: string | null
        period: string
        archive_type: string | null
        file_url: string
        file_encrypted: boolean | null
        retention_until: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id?: string
        period: string
        archive_type?: string
        file_url: string
        file_encrypted?: boolean
        retention_until?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        period?: string
        archive_type?: string
        file_url?: string
        file_encrypted?: boolean
        retention_until?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "payroll_archives_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    payroll_component_rates: {
      Row: {
        id: string
        tenant_id: string
        component_id: string
        legislation_pack: string | null
        rate_employer: number | null
        rate_employee: number | null
        ceiling_amount: number | null
        effective_date: string
        end_date: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        component_id: string
        legislation_pack?: string
        rate_employer?: number
        rate_employee?: number
        ceiling_amount?: number
        effective_date?: string
        end_date?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        component_id?: string
        legislation_pack?: string
        rate_employer?: number
        rate_employee?: number
        ceiling_amount?: number
        effective_date?: string
        end_date?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "payroll_component_rates_component_id_fkey",
          columns: ["tenant_id", "component_id"],
          isOneToOne: false,
          referencedRelation: "payroll_components",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id?: string
        code: string
        name: string
        type: string
        calculation_type?: string
        default_value?: number
        rate_employer?: number
        rate_employee?: number
        ceiling_amount?: number
        ceiling_basis?: string
        tax_deductible?: boolean
        display_order?: number
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        name?: string
        type?: string
        calculation_type?: string
        default_value?: number
        rate_employer?: number
        rate_employee?: number
        ceiling_amount?: number
        ceiling_basis?: string
        tax_deductible?: boolean
        display_order?: number
        active?: boolean
        created_at?: string
      }
      Relationships: [
      ]
    }
    payroll_cumulative: {
      Row: {
        id: string
        tenant_id: string
        employee_id: string
        year: number
        month: number
        gross: number | null
        taxable_gross: number | null
        ceiling_base: number | null
        ceiling_available: number | null
        net_taxable: number | null
        net_social: number | null
        employee_contributions: number | null
        employer_contributions: number | null
        withholding_tax: number | null
        csg_deductible: number | null
        csg_non_deductible: number | null
        crds: number | null
        reduction_generale: number | null
        overtime_exemption_used: number | null
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        year: number
        month: number
        gross?: number
        taxable_gross?: number
        ceiling_base?: number
        ceiling_available?: number
        net_taxable?: number
        net_social?: number
        employee_contributions?: number
        employer_contributions?: number
        withholding_tax?: number
        csg_deductible?: number
        csg_non_deductible?: number
        crds?: number
        reduction_generale?: number
        overtime_exemption_used?: number
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        year?: number
        month?: number
        gross?: number
        taxable_gross?: number
        ceiling_base?: number
        ceiling_available?: number
        net_taxable?: number
        net_social?: number
        employee_contributions?: number
        employer_contributions?: number
        withholding_tax?: number
        csg_deductible?: number
        csg_non_deductible?: number
        crds?: number
        reduction_generale?: number
        overtime_exemption_used?: number
      }
      Relationships: [
      ]
    }
    payroll_legal_parameters: {
      Row: {
        id: string
        tenant_id: string | null
        country_code: string
        code: string
        value: number
        valid_from: string
        valid_to: string | null
        source: string | null
      }
      Insert: {
        id?: string
        tenant_id?: string
        country_code: string
        code: string
        value: number
        valid_from: string
        valid_to?: string
        source?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        country_code?: string
        code?: string
        value?: number
        valid_from?: string
        valid_to?: string
        source?: string
      }
      Relationships: [
      ]
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
        ceiling_type: string | null
        ceiling_multiplier: number | null
        floor_multiplier: number | null
        ceiling_value: number | null
        cumulative_key: string | null
        section: string | null
        risk: string | null
        is_csg_crds: boolean | null
        csg_type: string | null
        eligible_reduction_generale: boolean | null
        applies_to: string
        company_size: string | null
        min_gross_pmss: number | null
        rate_employer_param: string | null
        source: string | null
      }
      Insert: {
        id?: string
        grid_id: string
        line_type: string
        category: string
        label: string
        base_type?: string
        min_amount?: number
        max_amount?: number
        rate_employee?: number
        rate_employer?: number
        cap_amount?: number
        fixed_amount?: number
        sort_order?: number
        created_at?: string
        ceiling_type?: string
        ceiling_multiplier?: number
        floor_multiplier?: number
        ceiling_value?: number
        cumulative_key?: string
        section?: string
        risk?: string
        is_csg_crds?: boolean
        csg_type?: string
        eligible_reduction_generale?: boolean
        applies_to?: string
        company_size?: string
        min_gross_pmss?: number
        rate_employer_param?: string
        source?: string
      }
      Update: {
        id?: string
        grid_id?: string
        line_type?: string
        category?: string
        label?: string
        base_type?: string
        min_amount?: number
        max_amount?: number
        rate_employee?: number
        rate_employer?: number
        cap_amount?: number
        fixed_amount?: number
        sort_order?: number
        created_at?: string
        ceiling_type?: string
        ceiling_multiplier?: number
        floor_multiplier?: number
        ceiling_value?: number
        cumulative_key?: string
        section?: string
        risk?: string
        is_csg_crds?: boolean
        csg_type?: string
        eligible_reduction_generale?: boolean
        applies_to?: string
        company_size?: string
        min_gross_pmss?: number
        rate_employer_param?: string
        source?: string
      }
      Relationships: [
        {
          foreignKeyName: "payroll_tax_grid_lines_grid_id_fkey",
          columns: ["grid_id"],
          isOneToOne: true,
          referencedRelation: "payroll_tax_grids",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id?: string
        country_code: string
        grid_type: string
        name: string
        description?: string
        effective_from?: string
        effective_to?: string
        status?: string
        source?: string
        file_url?: string
        is_default?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        country_code?: string
        grid_type?: string
        name?: string
        description?: string
        effective_from?: string
        effective_to?: string
        status?: string
        source?: string
        file_url?: string
        is_default?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "payroll_tax_grids_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: false,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    payroll_templates: {
      Row: {
        id: string
        tenant_id: string
        name: string
        category: string | null
        component_ids: Json | null
        description: string | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        category?: string
        component_ids?: Json
        description?: string
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        category?: string
        component_ids?: Json
        description?: string
        active?: boolean
        created_at?: string
      }
      Relationships: [
      ]
    }
    payroll_variable_elements: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        pay_run_id?: string
        period: string
        element_type: string
        description?: string
        quantity?: number
        unit_price?: number
        amount?: number
        source?: string
        source_id?: string
        integrated?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        pay_run_id?: string
        period?: string
        element_type?: string
        description?: string
        quantity?: number
        unit_price?: number
        amount?: number
        source?: string
        source_id?: string
        integrated?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "payroll_variable_elements_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "payroll_variable_elements_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "pve_pay_run_id_fkey",
          columns: ["tenant_id", "pay_run_id"],
          isOneToOne: false,
          referencedRelation: "pay_runs",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    pick_list_lines: {
      Row: {
        id: string
        tenant_id: string
        pick_list_id: string
        product_id: string
        location_id: string | null
        quantity_to_pick: number
        quantity_picked: number | null
        barcode: string | null
        created_at: string | null
        picked_quantity: number | null
        pick_order: number | null
      }
      Insert: {
        id?: string
        tenant_id: string
        pick_list_id: string
        product_id: string
        location_id?: string
        quantity_to_pick?: number
        quantity_picked?: number
        barcode?: string
        created_at?: string
        picked_quantity?: number
        pick_order?: number
      }
      Update: {
        id?: string
        tenant_id?: string
        pick_list_id?: string
        product_id?: string
        location_id?: string
        quantity_to_pick?: number
        quantity_picked?: number
        barcode?: string
        created_at?: string
        picked_quantity?: number
        pick_order?: number
      }
      Relationships: [
        {
          foreignKeyName: "pick_list_lines_location_id_fkey",
          columns: ["tenant_id", "location_id"],
          isOneToOne: false,
          referencedRelation: "warehouse_locations",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "pick_list_lines_pick_list_id_fkey",
          columns: ["tenant_id", "pick_list_id"],
          isOneToOne: false,
          referencedRelation: "pick_lists",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "pick_list_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    pick_lists: {
      Row: {
        id: string
        tenant_id: string
        number: string
        reference_type: string | null
        reference_id: string | null
        warehouse_id: string | null
        status: string | null
        picked_by: string | null
        picked_at: string | null
        created_at: string | null
        wave_id: string | null
        tour_id: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        number: string
        reference_type?: string
        reference_id?: string
        warehouse_id?: string
        status?: string
        picked_by?: string
        picked_at?: string
        created_at?: string
        wave_id?: string
        tour_id?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        number?: string
        reference_type?: string
        reference_id?: string
        warehouse_id?: string
        status?: string
        picked_by?: string
        picked_at?: string
        created_at?: string
        wave_id?: string
        tour_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "pick_lists_warehouse_id_fkey",
          columns: ["tenant_id", "warehouse_id"],
          isOneToOne: false,
          referencedRelation: "warehouses",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    planning_slots: {
      Row: {
        id: string
        tenant_id: string
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
        employee_id: string | null
        bloque_par_absence: boolean
      }
      Insert: {
        id?: string
        tenant_id: string
        manufacturing_order_id: string
        routing_operation_id?: string
        machine_id?: string
        work_center_id?: string
        planned_start?: string
        planned_end?: string
        setup_time?: number
        run_time?: number
        status?: string
        material_available?: boolean
        material_check_date?: string
        created_at?: string
        employee_id?: string
        bloque_par_absence?: boolean
      }
      Update: {
        id?: string
        tenant_id?: string
        manufacturing_order_id?: string
        routing_operation_id?: string
        machine_id?: string
        work_center_id?: string
        planned_start?: string
        planned_end?: string
        setup_time?: number
        run_time?: number
        status?: string
        material_available?: boolean
        material_check_date?: string
        created_at?: string
        employee_id?: string
        bloque_par_absence?: boolean
      }
      Relationships: [
        {
          foreignKeyName: "planning_slots_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "planning_slots_machine_id_fkey",
          columns: ["tenant_id", "machine_id"],
          isOneToOne: false,
          referencedRelation: "machines",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "planning_slots_manufacturing_order_id_fkey",
          columns: ["tenant_id", "manufacturing_order_id"],
          isOneToOne: false,
          referencedRelation: "manufacturing_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "planning_slots_routing_operation_id_fkey",
          columns: ["tenant_id", "routing_operation_id"],
          isOneToOne: false,
          referencedRelation: "routing_operations",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "planning_slots_work_center_id_fkey",
          columns: ["tenant_id", "work_center_id"],
          isOneToOne: false,
          referencedRelation: "work_centers",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    platform_admins: {
      Row: {
        auth_id: string
        created_at: string
      }
      Insert: {
        auth_id: string
        created_at?: string
      }
      Update: {
        auth_id?: string
        created_at?: string
      }
      Relationships: [
      ]
    }
    pos_payment_methods: {
      Row: {
        id: string
        tenant_id: string
        name: string
        type: string
        account_code: string
        opens_cash_drawer: boolean | null
        is_active: boolean | null
        display_order: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        type: string
        account_code: string
        opens_cash_drawer?: boolean
        is_active?: boolean
        display_order?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        type?: string
        account_code?: string
        opens_cash_drawer?: boolean
        is_active?: boolean
        display_order?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "pos_payment_methods_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    pos_payments: {
      Row: {
        id: string
        tenant_id: string
        ticket_id: string
        payment_method_id: string
        amount: number
        transaction_reference: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        ticket_id: string
        payment_method_id: string
        amount: number
        transaction_reference?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        ticket_id?: string
        payment_method_id?: string
        amount?: number
        transaction_reference?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "pos_payments_payment_method_id_fkey",
          columns: ["tenant_id", "payment_method_id"],
          isOneToOne: false,
          referencedRelation: "pos_payment_methods",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "pos_payments_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "pos_payments_ticket_id_fkey",
          columns: ["tenant_id", "ticket_id"],
          isOneToOne: false,
          referencedRelation: "pos_tickets",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    pos_sessions: {
      Row: {
        id: string
        tenant_id: string
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
        session_number: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        terminal_id: string
        user_email: string
        opening_amount?: number
        closing_amount?: number
        expected_amount?: number
        difference?: number
        status?: string
        opened_at?: string
        closed_at?: string
        notes?: string
        session_number?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        terminal_id?: string
        user_email?: string
        opening_amount?: number
        closing_amount?: number
        expected_amount?: number
        difference?: number
        status?: string
        opened_at?: string
        closed_at?: string
        notes?: string
        session_number?: string
      }
      Relationships: [
        {
          foreignKeyName: "pos_sessions_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "pos_sessions_terminal_id_fkey",
          columns: ["tenant_id", "terminal_id"],
          isOneToOne: false,
          referencedRelation: "pos_terminals",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    pos_terminals: {
      Row: {
        id: string
        tenant_id: string
        name: string
        warehouse_id: string | null
        location: string | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        warehouse_id?: string
        location?: string
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        warehouse_id?: string
        location?: string
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "pos_terminals_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "pos_terminals_warehouse_id_fkey",
          columns: ["tenant_id", "warehouse_id"],
          isOneToOne: false,
          referencedRelation: "warehouses",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    pos_ticket_lines: {
      Row: {
        id: string
        tenant_id: string
        ticket_id: string
        product_id: string | null
        description: string
        quantity: number
        unit_price: number
        vat_rate: number | null
        line_total: number
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        ticket_id: string
        product_id?: string
        description: string
        quantity?: number
        unit_price: number
        vat_rate?: number
        line_total: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        ticket_id?: string
        product_id?: string
        description?: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        line_total?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "pos_ticket_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "pos_ticket_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "pos_ticket_lines_ticket_id_fkey",
          columns: ["tenant_id", "ticket_id"],
          isOneToOne: false,
          referencedRelation: "pos_tickets",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    pos_tickets: {
      Row: {
        id: string
        tenant_id: string
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
        sequential_number: number | null
        ticket_hash: string | null
        previous_hash: string | null
        grand_total_daily: number | null
        grand_total_monthly: number | null
        grand_total_yearly: number | null
        grand_total_lifetime: number | null
        is_voided: boolean | null
        voided_at: string | null
        void_reason: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        number: string
        session_id: string
        terminal_id: string
        customer_id?: string
        date?: string
        subtotal?: number
        vat_total?: number
        total?: number
        payment_method?: string
        amount_paid?: number
        change_given?: number
        status?: string
        invoice_id?: string
        notes?: string
        created_at?: string
        sequential_number?: number
        ticket_hash?: string
        previous_hash?: string
        grand_total_daily?: number
        grand_total_monthly?: number
        grand_total_yearly?: number
        grand_total_lifetime?: number
        is_voided?: boolean
        voided_at?: string
        void_reason?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        number?: string
        session_id?: string
        terminal_id?: string
        customer_id?: string
        date?: string
        subtotal?: number
        vat_total?: number
        total?: number
        payment_method?: string
        amount_paid?: number
        change_given?: number
        status?: string
        invoice_id?: string
        notes?: string
        created_at?: string
        sequential_number?: number
        ticket_hash?: string
        previous_hash?: string
        grand_total_daily?: number
        grand_total_monthly?: number
        grand_total_yearly?: number
        grand_total_lifetime?: number
        is_voided?: boolean
        voided_at?: string
        void_reason?: string
      }
      Relationships: [
        {
          foreignKeyName: "pos_tickets_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "pos_tickets_session_id_fkey",
          columns: ["tenant_id", "session_id"],
          isOneToOne: false,
          referencedRelation: "pos_sessions",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "pos_tickets_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "pos_tickets_terminal_id_fkey",
          columns: ["tenant_id", "terminal_id"],
          isOneToOne: false,
          referencedRelation: "pos_terminals",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    price_list_customers: {
      Row: {
        price_list_id: string
        customer_id: string
        tenant_id: string
      }
      Insert: {
        price_list_id: string
        customer_id: string
        tenant_id: string
      }
      Update: {
        price_list_id?: string
        customer_id?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "price_list_customers_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "price_list_customers_price_list_id_fkey",
          columns: ["tenant_id", "price_list_id"],
          isOneToOne: false,
          referencedRelation: "price_lists",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
      Insert: {
        id?: string
        price_list_id?: string
        product_id?: string
        unit_price?: number
        min_quantity?: number
        discount_percent?: number
        tenant_id: string
      }
      Update: {
        id?: string
        price_list_id?: string
        product_id?: string
        unit_price?: number
        min_quantity?: number
        discount_percent?: number
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "price_list_lines_price_list_id_fkey",
          columns: ["tenant_id", "price_list_id"],
          isOneToOne: false,
          referencedRelation: "price_lists",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "price_list_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "price_list_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        priority: number | null
        customer_category_id: string | null
        base_price_list_id: string | null
        discount_percent: number | null
      }
      Insert: {
        id?: string
        name: string
        code?: string
        type?: string
        currency?: string
        valid_from?: string
        valid_to?: string
        active?: boolean
        is_default?: boolean
        created_at?: string
        tenant_id: string
        priority?: number
        customer_category_id?: string
        base_price_list_id?: string
        discount_percent?: number
      }
      Update: {
        id?: string
        name?: string
        code?: string
        type?: string
        currency?: string
        valid_from?: string
        valid_to?: string
        active?: boolean
        is_default?: boolean
        created_at?: string
        tenant_id?: string
        priority?: number
        customer_category_id?: string
        base_price_list_id?: string
        discount_percent?: number
      }
      Relationships: [
        {
          foreignKeyName: "price_lists_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    product_attributes: {
      Row: {
        id: string
        tenant_id: string
        name: string
        type: string
        options: Json | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        type?: string
        options?: Json
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        type?: string
        options?: Json
        created_at?: string
      }
      Relationships: [
      ]
    }
    product_batches: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        batch_number: string
        quantity: number
        expiry_date: string | null
        status: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        batch_number: string
        quantity?: number
        expiry_date?: string
        status?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        batch_number?: string
        quantity?: number
        expiry_date?: string
        status?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "product_batches_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    product_categories: {
      Row: {
        id: string
        tenant_id: string
        name: string
        parent_id: string | null
        sale_account_code: string | null
        purchase_account_code: string | null
        stock_account_code: string | null
        created_at: string | null
        updated_at: string | null
        variation_account_code: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        parent_id?: string
        sale_account_code?: string
        purchase_account_code?: string
        stock_account_code?: string
        created_at?: string
        updated_at?: string
        variation_account_code?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        parent_id?: string
        sale_account_code?: string
        purchase_account_code?: string
        stock_account_code?: string
        created_at?: string
        updated_at?: string
        variation_account_code?: string
      }
      Relationships: [
        {
          foreignKeyName: "product_categories_parent_id_fkey",
          columns: ["tenant_id", "parent_id"],
          isOneToOne: false,
          referencedRelation: "product_categories",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    product_equivalences: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        equivalent_product_id: string
        conversion_ratio: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        equivalent_product_id: string
        conversion_ratio?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        equivalent_product_id?: string
        conversion_ratio?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "product_equivalences_equivalent_product_id_fkey",
          columns: ["tenant_id", "equivalent_product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "product_equivalences_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    product_grid_combinations: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        combination: Json
        sku: string | null
        barcode: string | null
        price_override: number | null
        stock_quantity: number | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        combination: Json
        sku?: string
        barcode?: string
        price_override?: number
        stock_quantity?: number
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        combination?: Json
        sku?: string
        barcode?: string
        price_override?: number
        stock_quantity?: number
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "product_grid_combinations_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "product_grid_combinations_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    product_grids: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        name: string
        axis: string
        values: Json
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        name: string
        axis: string
        values?: Json
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        name?: string
        axis?: string
        values?: Json
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "product_grids_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "product_grids_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    product_links: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        linked_product_id: string
        link_type: string
        quantity: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        linked_product_id: string
        link_type: string
        quantity?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        linked_product_id?: string
        link_type?: string
        quantity?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "product_links_linked_product_id_fkey",
          columns: ["tenant_id", "linked_product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "product_links_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "product_links_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    product_packagings: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        name: string
        quantity: number
        unit: string | null
        barcode: string | null
        weight: number | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        name: string
        quantity: number
        unit?: string
        barcode?: string
        weight?: number
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        name?: string
        quantity?: number
        unit?: string
        barcode?: string
        weight?: number
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "product_packagings_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "product_packagings_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    product_serial_numbers: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        serial_number: string
        status: string | null
        warranty_expiry: string | null
        notes: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        serial_number: string
        status?: string
        warranty_expiry?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        serial_number?: string
        status?: string
        warranty_expiry?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "product_serial_numbers_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    product_substitutes: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        substitute_id: string
        priority: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        substitute_id: string
        priority?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        substitute_id?: string
        priority?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "product_substitutes_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "product_substitutes_substitute_id_fkey",
          columns: ["tenant_id", "substitute_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    product_variants: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        sku: string
        attributes: Json | null
        price_override: number | null
        barcode: string | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        sku: string
        attributes?: Json
        price_override?: number
        barcode?: string
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        sku?: string
        attributes?: Json
        price_override?: number
        barcode?: string
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "product_variants_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    production_forecasts: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        forecast_number: string
        period: string
        start_date: string
        end_date: string
        product_id?: string
        forecasted_quantity?: number
        actual_quantity?: number
        reliability_rate?: number
        source?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        forecast_number?: string
        period?: string
        start_date?: string
        end_date?: string
        product_id?: string
        forecasted_quantity?: number
        actual_quantity?: number
        reliability_rate?: number
        source?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "production_forecasts_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
        sale_account_code: string | null
        purchase_account_code: string | null
        stock_account_code: string | null
        category_id: string | null
        safety_stock: number | null
        lead_time_days: number | null
        min_order_qty: number | null
        qty_multiple: number | null
        scrap_rate: number | null
        tracking: string | null
        import_batch_id: string | null
        uom_id: string | null
        purchase_uom_id: string | null
        sale_uom_id: string | null
      }
      Insert: {
        id?: string
        name: string
        sku?: string
        description?: string
        type: string
        sale_price?: number
        purchase_price?: number
        vat_rate?: number
        stock_quantity?: number
        reorder_level?: number
        unit?: string
        category?: string
        active?: boolean
        created_at?: string
        updated_at?: string
        tenant_id: string
        is_amalgam?: boolean
        units_per_carton?: number
        st_unit?: string
        purchase_unit?: string
        st_multiple?: number
        shelf_life_days?: number
        exclude_from_mrp?: boolean
        barcode?: string
        weight?: number
        photo_url?: string
        supplier_ref?: string
        criticality_level?: string
        cost_price?: number
        sale_account_code?: string
        purchase_account_code?: string
        stock_account_code?: string
        category_id?: string
        safety_stock?: number
        lead_time_days?: number
        min_order_qty?: number
        qty_multiple?: number
        scrap_rate?: number
        tracking?: string
        import_batch_id?: string
        uom_id?: string
        purchase_uom_id?: string
        sale_uom_id?: string
      }
      Update: {
        id?: string
        name?: string
        sku?: string
        description?: string
        type?: string
        sale_price?: number
        purchase_price?: number
        vat_rate?: number
        stock_quantity?: number
        reorder_level?: number
        unit?: string
        category?: string
        active?: boolean
        created_at?: string
        updated_at?: string
        tenant_id?: string
        is_amalgam?: boolean
        units_per_carton?: number
        st_unit?: string
        purchase_unit?: string
        st_multiple?: number
        shelf_life_days?: number
        exclude_from_mrp?: boolean
        barcode?: string
        weight?: number
        photo_url?: string
        supplier_ref?: string
        criticality_level?: string
        cost_price?: number
        sale_account_code?: string
        purchase_account_code?: string
        stock_account_code?: string
        category_id?: string
        safety_stock?: number
        lead_time_days?: number
        min_order_qty?: number
        qty_multiple?: number
        scrap_rate?: number
        tracking?: string
        import_batch_id?: string
        uom_id?: string
        purchase_uom_id?: string
        sale_uom_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "products_category_fk",
          columns: ["tenant_id", "category_id"],
          isOneToOne: false,
          referencedRelation: "product_categories",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "products_purchase_uom_id_fkey",
          columns: ["tenant_id", "purchase_uom_id"],
          isOneToOne: false,
          referencedRelation: "uoms",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "products_sale_uom_id_fkey",
          columns: ["tenant_id", "sale_uom_id"],
          isOneToOne: false,
          referencedRelation: "uoms",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "products_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "products_uom_id_fkey",
          columns: ["tenant_id", "uom_id"],
          isOneToOne: false,
          referencedRelation: "uoms",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
        old_value: Json | null
        new_value: Json | null
        description: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        task_id?: string
        project_id?: string
        user_id?: string
        user_name?: string
        action_type: string
        old_value?: Json
        new_value?: Json
        description?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        task_id?: string
        project_id?: string
        user_id?: string
        user_name?: string
        action_type?: string
        old_value?: Json
        new_value?: Json
        description?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "project_activity_log_project_id_fkey",
          columns: ["tenant_id", "project_id"],
          isOneToOne: false,
          referencedRelation: "projects",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_activity_log_task_id_fkey",
          columns: ["tenant_id", "task_id"],
          isOneToOne: false,
          referencedRelation: "project_tasks",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_activity_log_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id: string
        project_id?: string
        title?: string
        content?: string
        created_by?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        project_id?: string
        title?: string
        content?: string
        created_by?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "project_docs_project_id_fkey",
          columns: ["tenant_id", "project_id"],
          isOneToOne: false,
          referencedRelation: "projects",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id: string
        project_id: string
        employee_id: string
        role?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        project_id?: string
        employee_id?: string
        role?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "project_members_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_members_project_id_fkey",
          columns: ["tenant_id", "project_id"],
          isOneToOne: false,
          referencedRelation: "projects",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_members_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id: string
        project_id: string
        name: string
        deadline?: string
        is_reached?: boolean
        is_reached_manually?: boolean
        sale_line_id?: string
        sale_line_qty_percentage?: number
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        project_id?: string
        name?: string
        deadline?: string
        is_reached?: boolean
        is_reached_manually?: boolean
        sale_line_id?: string
        sale_line_qty_percentage?: number
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "project_milestones_project_id_fkey",
          columns: ["tenant_id", "project_id"],
          isOneToOne: false,
          referencedRelation: "projects",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_milestones_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id: string
        recipient_id: string
        task_id?: string
        project_id?: string
        notification_type: string
        title: string
        message?: string
        is_read?: boolean
        action_url?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        recipient_id?: string
        task_id?: string
        project_id?: string
        notification_type?: string
        title?: string
        message?: string
        is_read?: boolean
        action_url?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "project_notifications_project_id_fkey",
          columns: ["tenant_id", "project_id"],
          isOneToOne: false,
          referencedRelation: "projects",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_notifications_recipient_id_fkey",
          columns: ["tenant_id", "recipient_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_notifications_task_id_fkey",
          columns: ["tenant_id", "task_id"],
          isOneToOne: false,
          referencedRelation: "project_tasks",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_notifications_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id: string
        name: string
        sequence?: number
        fold?: boolean
        case_default?: boolean
        mail_template_id?: string
        legend_priority?: string
        legend_blocked?: string
        legend_done?: string
        legend_normal?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        sequence?: number
        fold?: boolean
        case_default?: boolean
        mail_template_id?: string
        legend_priority?: string
        legend_blocked?: string
        legend_done?: string
        legend_normal?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "project_stages_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    project_tags: {
      Row: {
        id: string
        tenant_id: string
        name: string
        color: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        color?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        color?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "project_tags_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    project_task_assignees: {
      Row: {
        task_id: string
        employee_id: string
      }
      Insert: {
        task_id: string
        employee_id: string
      }
      Update: {
        task_id?: string
        employee_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "project_task_assignees_employee_id_fkey",
          columns: ["employee_id"],
          isOneToOne: true,
          referencedRelation: "employees",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "project_task_assignees_task_id_fkey",
          columns: ["task_id"],
          isOneToOne: true,
          referencedRelation: "project_tasks",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id: string
        task_id: string
        depends_on_task_id: string
        dependency_type?: string
        lag_days?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        task_id?: string
        depends_on_task_id?: string
        dependency_type?: string
        lag_days?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "project_task_dependencies_depends_on_task_id_fkey",
          columns: ["tenant_id", "depends_on_task_id"],
          isOneToOne: false,
          referencedRelation: "project_tasks",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_task_dependencies_task_id_fkey",
          columns: ["tenant_id", "task_id"],
          isOneToOne: false,
          referencedRelation: "project_tasks",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_task_dependencies_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    project_task_tags: {
      Row: {
        task_id: string
        tag_id: string
        tenant_id: string
      }
      Insert: {
        task_id: string
        tag_id: string
        tenant_id: string
      }
      Update: {
        task_id?: string
        tag_id?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "project_task_tags_tag_id_fkey",
          columns: ["tenant_id", "tag_id"],
          isOneToOne: false,
          referencedRelation: "project_tags",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_task_tags_task_id_fkey",
          columns: ["tenant_id", "task_id"],
          isOneToOne: false,
          referencedRelation: "project_tasks",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_task_tags_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        default_tags: string[] | null
        default_effort_estimate: number | null
        default_budget: number | null
        checklist_template: Json | null
        subtasks_template: Json | null
        is_public: boolean | null
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        description?: string
        default_status?: string
        default_priority?: string
        default_assignee_id?: string
        default_tags?: string[]
        default_effort_estimate?: number
        default_budget?: number
        checklist_template?: Json
        subtasks_template?: Json
        is_public?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        description?: string
        default_status?: string
        default_priority?: string
        default_assignee_id?: string
        default_tags?: string[]
        default_effort_estimate?: number
        default_budget?: number
        checklist_template?: Json
        subtasks_template?: Json
        is_public?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "project_task_templates_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    project_task_watchers: {
      Row: {
        id: string
        tenant_id: string
        task_id: string
        employee_id: string
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        task_id: string
        employee_id: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        task_id?: string
        employee_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "project_task_watchers_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_task_watchers_task_id_fkey",
          columns: ["tenant_id", "task_id"],
          isOneToOne: false,
          referencedRelation: "project_tasks",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_task_watchers_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        milestone_id: string | null
        subtask_count: number | null
        subtask_done_count: number | null
        subtask_effective_hours: number | null
        predecessor_ids: string[] | null
        early_start: string | null
        early_finish: string | null
        late_start: string | null
        late_finish: string | null
        total_slack: number | null
        is_critical_path: boolean | null
      }
      Insert: {
        id?: string
        tenant_id: string
        project_id?: string
        parent_id?: string
        title: string
        description?: string
        status?: string
        priority?: string
        assignee?: string
        start_date?: string
        due_date?: string
        effort_estimate_h?: number
        effort_spent_h?: number
        progress?: number
        display_order?: string
        task_level?: number
        budget?: number
        color?: number
        acceptance_criteria?: string
        recurring_task?: boolean
        recurring_interval?: number
        recurring_rule_type?: string
        is_closed?: boolean
        linked_action_id?: string
        created_at?: string
        updated_at?: string
        assignee_id?: string
        milestone_id?: string
        subtask_count?: number
        subtask_done_count?: number
        subtask_effective_hours?: number
        predecessor_ids?: string[]
        early_start?: string
        early_finish?: string
        late_start?: string
        late_finish?: string
        total_slack?: number
        is_critical_path?: boolean
      }
      Update: {
        id?: string
        tenant_id?: string
        project_id?: string
        parent_id?: string
        title?: string
        description?: string
        status?: string
        priority?: string
        assignee?: string
        start_date?: string
        due_date?: string
        effort_estimate_h?: number
        effort_spent_h?: number
        progress?: number
        display_order?: string
        task_level?: number
        budget?: number
        color?: number
        acceptance_criteria?: string
        recurring_task?: boolean
        recurring_interval?: number
        recurring_rule_type?: string
        is_closed?: boolean
        linked_action_id?: string
        created_at?: string
        updated_at?: string
        assignee_id?: string
        milestone_id?: string
        subtask_count?: number
        subtask_done_count?: number
        subtask_effective_hours?: number
        predecessor_ids?: string[]
        early_start?: string
        early_finish?: string
        late_start?: string
        late_finish?: string
        total_slack?: number
        is_critical_path?: boolean
      }
      Relationships: [
        {
          foreignKeyName: "project_tasks_assignee_id_fkey",
          columns: ["tenant_id", "assignee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_tasks_milestone_id_fkey",
          columns: ["tenant_id", "milestone_id"],
          isOneToOne: false,
          referencedRelation: "project_milestones",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_tasks_parent_id_fkey",
          columns: ["tenant_id", "parent_id"],
          isOneToOne: false,
          referencedRelation: "project_tasks",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_tasks_project_id_fkey",
          columns: ["tenant_id", "project_id"],
          isOneToOne: false,
          referencedRelation: "projects",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_tasks_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        tags: string[] | null
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        task_id?: string
        project_id?: string
        employee_id?: string
        start_time?: string
        end_time?: string
        duration_seconds?: number
        description?: string
        is_billable?: boolean
        hourly_rate?: number
        tags?: string[]
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        task_id?: string
        project_id?: string
        employee_id?: string
        start_time?: string
        end_time?: string
        duration_seconds?: number
        description?: string
        is_billable?: boolean
        hourly_rate?: number
        tags?: string[]
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "project_time_entries_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_time_entries_project_id_fkey",
          columns: ["tenant_id", "project_id"],
          isOneToOne: false,
          referencedRelation: "projects",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_time_entries_task_id_fkey",
          columns: ["tenant_id", "task_id"],
          isOneToOne: false,
          referencedRelation: "project_tasks",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "project_time_entries_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        baseline_start_date: string | null
        baseline_end_date: string | null
        baseline_budget: number | null
      }
      Insert: {
        id?: string
        name: string
        description?: string
        customer_id?: string
        status?: string
        budget?: number
        actual_cost?: number
        start_date?: string
        end_date?: string
        created_at?: string
        updated_at?: string
        tenant_id: string
        color?: string
        display_order?: string
        progress?: number
        manager_id?: string
        allow_subtasks?: boolean
        allow_recurrent_tasks?: boolean
        allow_milestones?: boolean
        allow_task_dependencies?: boolean
        allow_timesheets?: boolean
        allow_billable?: boolean
        privacy_visibility?: string
        alias_name?: string
        allocated_hours?: number
        total_hours_spent?: number
        remaining_hours?: number
        baseline_start_date?: string
        baseline_end_date?: string
        baseline_budget?: number
      }
      Update: {
        id?: string
        name?: string
        description?: string
        customer_id?: string
        status?: string
        budget?: number
        actual_cost?: number
        start_date?: string
        end_date?: string
        created_at?: string
        updated_at?: string
        tenant_id?: string
        color?: string
        display_order?: string
        progress?: number
        manager_id?: string
        allow_subtasks?: boolean
        allow_recurrent_tasks?: boolean
        allow_milestones?: boolean
        allow_task_dependencies?: boolean
        allow_timesheets?: boolean
        allow_billable?: boolean
        privacy_visibility?: string
        alias_name?: string
        allocated_hours?: number
        total_hours_spent?: number
        remaining_hours?: number
        baseline_start_date?: string
        baseline_end_date?: string
        baseline_budget?: number
      }
      Relationships: [
        {
          foreignKeyName: "proj_manager_id_fkey",
          columns: ["tenant_id", "manager_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "projects_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "projects_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    promotions: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        name: string
        description?: string
        promo_type: string
        value?: number
        product_id?: string
        category?: string
        customer_id?: string
        start_date: string
        end_date: string
        min_quantity?: number
        free_product_id?: string
        free_product_qty?: number
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        description?: string
        promo_type?: string
        value?: number
        product_id?: string
        category?: string
        customer_id?: string
        start_date?: string
        end_date?: string
        min_quantity?: number
        free_product_id?: string
        free_product_qty?: number
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "promotions_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "promotions_free_product_id_fkey",
          columns: ["tenant_id", "free_product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "promotions_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "promotions_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    prospects: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        name: string
        email?: string
        phone?: string
        address?: string
        city?: string
        postal_code?: string
        country?: string
        contact_name?: string
        source?: string
        status?: string
        assigned_rep_id?: string
        notes?: string
        converted_customer_id?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        email?: string
        phone?: string
        address?: string
        city?: string
        postal_code?: string
        country?: string
        contact_name?: string
        source?: string
        status?: string
        assigned_rep_id?: string
        notes?: string
        converted_customer_id?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "prospects_assigned_rep_id_fkey",
          columns: ["tenant_id", "assigned_rep_id"],
          isOneToOne: false,
          referencedRelation: "sales_representatives",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "prospects_converted_customer_id_fkey",
          columns: ["tenant_id", "converted_customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id?: string
        name: string
        holiday_date: string
        region?: string
        country?: string
        is_working_day?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        holiday_date?: string
        region?: string
        country?: string
        is_working_day?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "public_holidays_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: false,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        product_id: string | null
        vat_code: string | null
        vat_amount: number
      }
      Insert: {
        id?: string
        purchase_credit_id?: string
        description: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        total?: number
        vat_total?: number
        line_order?: number
        created_at?: string
        tenant_id: string
        product_id?: string
        vat_code?: string
        vat_amount?: number
      }
      Update: {
        id?: string
        purchase_credit_id?: string
        description?: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        total?: number
        vat_total?: number
        line_order?: number
        created_at?: string
        tenant_id?: string
        product_id?: string
        vat_code?: string
        vat_amount?: number
      }
      Relationships: [
        {
          foreignKeyName: "purchase_credit_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_credit_lines_purchase_credit_id_fkey",
          columns: ["tenant_id", "purchase_credit_id"],
          isOneToOne: false,
          referencedRelation: "purchase_credit_notes",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_credit_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        transferred_entry_id: string | null
        supplier_reference: string | null
        validated_at: string | null
      }
      Insert: {
        id?: string
        number: string
        supplier_id?: string
        supplier_name?: string
        date?: string
        status?: string
        subtotal?: number
        vat_total?: number
        total?: number
        reason?: string
        purchase_invoice_id?: string
        created_at?: string
        tenant_id: string
        currency_code?: string
        exchange_rate?: number
        amount_untaxed_currency?: number
        amount_tax_currency?: number
        amount_total_currency?: number
        transferred_entry_id?: string
        supplier_reference?: string
        validated_at?: string
      }
      Update: {
        id?: string
        number?: string
        supplier_id?: string
        supplier_name?: string
        date?: string
        status?: string
        subtotal?: number
        vat_total?: number
        total?: number
        reason?: string
        purchase_invoice_id?: string
        created_at?: string
        tenant_id?: string
        currency_code?: string
        exchange_rate?: number
        amount_untaxed_currency?: number
        amount_tax_currency?: number
        amount_total_currency?: number
        transferred_entry_id?: string
        supplier_reference?: string
        validated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "purchase_credit_notes_purchase_invoice_id_fkey",
          columns: ["tenant_id", "purchase_invoice_id"],
          isOneToOne: false,
          referencedRelation: "purchase_invoices",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_credit_notes_supplier_id_fkey",
          columns: ["tenant_id", "supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_credit_notes_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "purchase_credit_notes_transferred_entry_id_fkey",
          columns: ["tenant_id", "transferred_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
        purchase_order_line_id: string | null
        quantity_received: number | null
        vat_code: string | null
        vat_amount: number | null
        analytic_section_id: string | null
      }
      Insert: {
        id?: string
        purchase_invoice_id?: string
        product_id?: string
        description: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        total?: number
        vat_total?: number
        line_order?: number
        created_at?: string
        tenant_id: string
        purchase_order_line_id?: string
        quantity_received?: number
        vat_code?: string
        vat_amount?: number
        analytic_section_id?: string
      }
      Update: {
        id?: string
        purchase_invoice_id?: string
        product_id?: string
        description?: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        total?: number
        vat_total?: number
        line_order?: number
        created_at?: string
        tenant_id?: string
        purchase_order_line_id?: string
        quantity_received?: number
        vat_code?: string
        vat_amount?: number
        analytic_section_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "purchase_invoice_lines_analytic_section_fk",
          columns: ["tenant_id", "analytic_section_id"],
          isOneToOne: false,
          referencedRelation: "analytic_sections",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_invoice_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_invoice_lines_purchase_invoice_id_fkey",
          columns: ["tenant_id", "purchase_invoice_id"],
          isOneToOne: false,
          referencedRelation: "purchase_invoices",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_invoice_lines_purchase_order_line_id_fkey",
          columns: ["tenant_id", "purchase_order_line_id"],
          isOneToOne: false,
          referencedRelation: "purchase_order_lines",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_invoice_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        purchase_order_id: string | null
        goods_receipt_id: string | null
        match_status: string | null
        match_details: Json | null
        supplier_reference: string | null
        created_by: string | null
      }
      Insert: {
        id?: string
        number: string
        supplier_id?: string
        supplier_name?: string
        date?: string
        due_date: string
        status?: string
        subtotal?: number
        vat_total?: number
        total?: number
        amount_paid?: number
        amount_due?: number
        notes?: string
        created_at?: string
        updated_at?: string
        tenant_id: string
        approval_status?: string
        approved_by?: string
        approved_at?: string
        fiscal_position_id?: string
        payment_state?: string
        currency_code?: string
        exchange_rate?: number
        amount_untaxed_currency?: number
        amount_tax_currency?: number
        amount_total_currency?: number
        transferred_entry_id?: string
        purchase_order_id?: string
        goods_receipt_id?: string
        match_status?: string
        match_details?: Json
        supplier_reference?: string
        created_by?: string
      }
      Update: {
        id?: string
        number?: string
        supplier_id?: string
        supplier_name?: string
        date?: string
        due_date?: string
        status?: string
        subtotal?: number
        vat_total?: number
        total?: number
        amount_paid?: number
        amount_due?: number
        notes?: string
        created_at?: string
        updated_at?: string
        tenant_id?: string
        approval_status?: string
        approved_by?: string
        approved_at?: string
        fiscal_position_id?: string
        payment_state?: string
        currency_code?: string
        exchange_rate?: number
        amount_untaxed_currency?: number
        amount_tax_currency?: number
        amount_total_currency?: number
        transferred_entry_id?: string
        purchase_order_id?: string
        goods_receipt_id?: string
        match_status?: string
        match_details?: Json
        supplier_reference?: string
        created_by?: string
      }
      Relationships: [
        {
          foreignKeyName: "purchase_invoices_fiscal_position_id_fkey",
          columns: ["tenant_id", "fiscal_position_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_positions",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_invoices_goods_receipt_id_fkey",
          columns: ["tenant_id", "goods_receipt_id"],
          isOneToOne: false,
          referencedRelation: "goods_receipts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_invoices_purchase_order_id_fkey",
          columns: ["tenant_id", "purchase_order_id"],
          isOneToOne: false,
          referencedRelation: "purchase_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_invoices_supplier_id_fkey",
          columns: ["tenant_id", "supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_invoices_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "purchase_invoices_transferred_entry_id_fkey",
          columns: ["tenant_id", "transferred_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
        line_order: number | null
      }
      Insert: {
        id?: string
        purchase_order_id?: string
        product_id?: string
        description: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        line_total?: number
        tenant_id: string
        line_order?: number
      }
      Update: {
        id?: string
        purchase_order_id?: string
        product_id?: string
        description?: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        line_total?: number
        tenant_id?: string
        line_order?: number
      }
      Relationships: [
        {
          foreignKeyName: "purchase_order_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_order_lines_purchase_order_id_fkey",
          columns: ["tenant_id", "purchase_order_id"],
          isOneToOne: false,
          referencedRelation: "purchase_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_order_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        number: string
        supplier_id?: string
        order_date?: string
        expected_date?: string
        status?: string
        subtotal?: number
        vat?: number
        total?: number
        notes?: string
        created_at?: string
        updated_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        number?: string
        supplier_id?: string
        order_date?: string
        expected_date?: string
        status?: string
        subtotal?: number
        vat?: number
        total?: number
        notes?: string
        created_at?: string
        updated_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "purchase_orders_supplier_id_fkey",
          columns: ["tenant_id", "supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_orders_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    purchase_request_lines: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        purchase_request_id: string
        product_id?: string
        description: string
        quantity?: number
        unit?: string
        estimated_price?: number
        preferred_supplier_id?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        purchase_request_id?: string
        product_id?: string
        description?: string
        quantity?: number
        unit?: string
        estimated_price?: number
        preferred_supplier_id?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "purchase_request_lines_preferred_supplier_id_fkey",
          columns: ["tenant_id", "preferred_supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_request_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_request_lines_purchase_request_id_fkey",
          columns: ["tenant_id", "purchase_request_id"],
          isOneToOne: false,
          referencedRelation: "purchase_requests",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "purchase_request_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    purchase_requests: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        number: string
        requester?: string
        department?: string
        status?: string
        priority?: string
        expected_date?: string
        notes?: string
        approved_by?: string
        approved_at?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        number?: string
        requester?: string
        department?: string
        status?: string
        priority?: string
        expected_date?: string
        notes?: string
        approved_by?: string
        approved_at?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "purchase_requests_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    quality_checks: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        reference_type: string | null
        reference_id: string | null
        status: string | null
        checked_by: string | null
        checked_at: string | null
        notes: string | null
        created_at: string | null
        quantity_checked: number | null
        quantity_rejected: number | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        reference_type?: string
        reference_id?: string
        status?: string
        checked_by?: string
        checked_at?: string
        notes?: string
        created_at?: string
        quantity_checked?: number
        quantity_rejected?: number
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        reference_type?: string
        reference_id?: string
        status?: string
        checked_by?: string
        checked_at?: string
        notes?: string
        created_at?: string
        quantity_checked?: number
        quantity_rejected?: number
      }
      Relationships: [
        {
          foreignKeyName: "quality_checks_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    quality_control_plans: {
      Row: {
        id: string
        tenant_id: string
        product_id: string | null
        category_id: string | null
        name: string
        is_active: boolean | null
        sampling_method: string | null
        sampling_rate: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id?: string
        category_id?: string
        name: string
        is_active?: boolean
        sampling_method?: string
        sampling_rate?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        category_id?: string
        name?: string
        is_active?: boolean
        sampling_method?: string
        sampling_rate?: number
        created_at?: string
      }
      Relationships: [
      ]
    }
    quality_control_points: {
      Row: {
        id: string
        tenant_id: string
        plan_id: string
        name: string
        check_type: string
        tolerance_min: number | null
        tolerance_max: number | null
        unit: string | null
        is_mandatory: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        plan_id: string
        name: string
        check_type: string
        tolerance_min?: number
        tolerance_max?: number
        unit?: string
        is_mandatory?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        plan_id?: string
        name?: string
        check_type?: string
        tolerance_min?: number
        tolerance_max?: number
        unit?: string
        is_mandatory?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "quality_control_points_plan_id_fkey",
          columns: ["tenant_id", "plan_id"],
          isOneToOne: false,
          referencedRelation: "quality_control_plans",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
      Insert: {
        id?: string
        quote_id?: string
        product_id?: string
        description: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        total?: number
        vat_total?: number
        line_order?: number
        created_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        quote_id?: string
        product_id?: string
        description?: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        total?: number
        vat_total?: number
        line_order?: number
        created_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "quote_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "quote_lines_quote_id_fkey",
          columns: ["tenant_id", "quote_id"],
          isOneToOne: false,
          referencedRelation: "quotes",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "quote_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        number: string
        customer_id?: string
        customer_name?: string
        date?: string
        expiry_date: string
        status?: string
        subtotal?: number
        vat_total?: number
        total?: number
        notes?: string
        created_at?: string
        updated_at?: string
        tenant_id: string
        validation_status?: string
        transformed_to_order_id?: string
        transformation_status?: string
      }
      Update: {
        id?: string
        number?: string
        customer_id?: string
        customer_name?: string
        date?: string
        expiry_date?: string
        status?: string
        subtotal?: number
        vat_total?: number
        total?: number
        notes?: string
        created_at?: string
        updated_at?: string
        tenant_id?: string
        validation_status?: string
        transformed_to_order_id?: string
        transformation_status?: string
      }
      Relationships: [
        {
          foreignKeyName: "quotes_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "quotes_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "quotes_transformed_to_order_id_fkey",
          columns: ["tenant_id", "transformed_to_order_id"],
          isOneToOne: false,
          referencedRelation: "sales_orders",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    recurring_entries: {
      Row: {
        id: string
        tenant_id: string
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
        lines: Json
        status: string
        total_debit: number
        total_credit: number
        created_at: string
        updated_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        description?: string
        journal_id: string
        journal_code?: string
        frequency?: string
        day_of_month?: number
        start_date: string
        end_date?: string
        next_generation_date: string
        last_generation_date?: string
        lines?: Json
        status?: string
        total_debit?: number
        total_credit?: number
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        description?: string
        journal_id?: string
        journal_code?: string
        frequency?: string
        day_of_month?: number
        start_date?: string
        end_date?: string
        next_generation_date?: string
        last_generation_date?: string
        lines?: Json
        status?: string
        total_debit?: number
        total_credit?: number
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "recurring_entries_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    recurring_invoice_templates: {
      Row: {
        id: string
        tenant_id: string
        name: string
        customer_id: string | null
        frequency: string | null
        next_date: string
        lines: Json | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        customer_id?: string
        frequency?: string
        next_date?: string
        lines?: Json
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        customer_id?: string
        frequency?: string
        next_date?: string
        lines?: Json
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "recurring_invoice_templates_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    regularization_entries: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        type: string
        fiscal_year_id?: string
        account_code: string
        third_party_code?: string
        description: string
        invoice_number?: string
        invoice_date?: string
        invoice_amount?: number
        start_date: string
        end_date: string
        amount?: number
        used_amount?: number
        remaining_amount?: number
        status?: string
        journal_id?: string
        journal_code?: string
        created_entry_id?: string
        extourne_entry_id?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        type?: string
        fiscal_year_id?: string
        account_code?: string
        third_party_code?: string
        description?: string
        invoice_number?: string
        invoice_date?: string
        invoice_amount?: number
        start_date?: string
        end_date?: string
        amount?: number
        used_amount?: number
        remaining_amount?: number
        status?: string
        journal_id?: string
        journal_code?: string
        created_entry_id?: string
        extourne_entry_id?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "reg_created_entry_id_fkey",
          columns: ["tenant_id", "created_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "reg_fiscal_year_id_fkey",
          columns: ["tenant_id", "fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "regularization_entries_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    reimputation_logs: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        original_entry_id?: string
        original_line_id?: string
        reimputed_entry_id?: string
        reimputed_line_id?: string
        from_account: string
        to_account: string
        amount?: number
        reason?: string
        status?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        original_entry_id?: string
        original_line_id?: string
        reimputed_entry_id?: string
        reimputed_line_id?: string
        from_account?: string
        to_account?: string
        amount?: number
        reason?: string
        status?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "reimputation_logs_original_entry_id_fkey",
          columns: ["tenant_id", "original_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "reimputation_logs_original_line_id_fkey",
          columns: ["tenant_id", "original_line_id"],
          isOneToOne: false,
          referencedRelation: "journal_lines",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "reimputation_logs_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "rl_reimputed_entry_id_fkey",
          columns: ["tenant_id", "reimputed_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    reminder_levels: {
      Row: {
        id: string
        tenant_id: string
        level: number
        name: string
        template: string | null
        days_after_due: number
        penalty_rate: number | null
        active: boolean | null
        created_at: string
        updated_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        level: number
        name: string
        template?: string
        days_after_due?: number
        penalty_rate?: number
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        level?: number
        name?: string
        template?: string
        days_after_due?: number
        penalty_rate?: number
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "reminder_levels_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    reorder_rules: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        warehouse_id: string | null
        min_quantity: number
        max_quantity: number
        multiple_quantity: number | null
        lead_time_days: number | null
        is_active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        warehouse_id?: string
        min_quantity: number
        max_quantity: number
        multiple_quantity?: number
        lead_time_days?: number
        is_active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        warehouse_id?: string
        min_quantity?: number
        max_quantity?: number
        multiple_quantity?: number
        lead_time_days?: number
        is_active?: boolean
        created_at?: string
      }
      Relationships: [
      ]
    }
    reporting_plans: {
      Row: {
        id: string
        tenant_id: string
        name: string
        report_type: string
        schedule: string
        format: string
        recipients: string | null
        parameters: Json | null
        last_generated: string | null
        active: boolean | null
        created_at: string
        updated_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        report_type: string
        schedule?: string
        format?: string
        recipients?: string
        parameters?: Json
        last_generated?: string
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        report_type?: string
        schedule?: string
        format?: string
        recipients?: string
        parameters?: Json
        last_generated?: string
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "reporting_plans_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    revision_cycles: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        name: string
        frequency?: string
        start_month?: number
        account_class?: string
        active?: boolean
        last_run?: string
        next_run?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        frequency?: string
        start_month?: number
        account_class?: string
        active?: boolean
        last_run?: string
        next_run?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "revision_cycles_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    rgpd_requests: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        request_type: string
        entity_type: string
        entity_id?: string
        status?: string
        requested_by?: string
        processed_by?: string
        requested_at?: string
        processed_at?: string
        notes?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        request_type?: string
        entity_type?: string
        entity_id?: string
        status?: string
        requested_by?: string
        processed_by?: string
        requested_at?: string
        processed_at?: string
        notes?: string
      }
      Relationships: [
        {
          foreignKeyName: "rgpd_requests_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    rh_dashboard_configs: {
      Row: {
        id: string
        tenant_id: string
        user_email: string
        dashboard_type: string
        widgets: Json | null
        filters: Json | null
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        user_email: string
        dashboard_type: string
        widgets?: Json
        filters?: Json
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        user_email?: string
        dashboard_type?: string
        widgets?: Json
        filters?: Json
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "rh_dashboard_configs_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    rh_knowledge_base: {
      Row: {
        id: string
        tenant_id: string
        title: string
        content: string
        category: string | null
        tags: string[] | null
        author_id: string | null
        published: boolean | null
        views: number | null
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        title: string
        content: string
        category?: string
        tags?: string[]
        author_id?: string
        published?: boolean
        views?: number
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        title?: string
        content?: string
        category?: string
        tags?: string[]
        author_id?: string
        published?: boolean
        views?: number
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "rh_knowledge_base_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    rh_reports: {
      Row: {
        id: string
        tenant_id: string
        name: string
        report_type: string
        parameters: Json | null
        chart_type: string | null
        data: Json | null
        data_calculated_at: string | null
        created_by: string | null
        shared: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        report_type: string
        parameters?: Json
        chart_type?: string
        data?: Json
        data_calculated_at?: string
        created_by?: string
        shared?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        report_type?: string
        parameters?: Json
        chart_type?: string
        data?: Json
        data_calculated_at?: string
        created_by?: string
        shared?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "rh_reports_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    rh_requests: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        request_type: string
        subject: string
        description?: string
        status?: string
        assigned_to?: string
        response?: string
        resolved_at?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        request_type?: string
        subject?: string
        description?: string
        status?: string
        assigned_to?: string
        response?: string
        resolved_at?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "rh_requests_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "rh_requests_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    role_permissions: {
      Row: {
        id: string
        tenant_id: string
        role_id: string
        permission: string
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        role_id: string
        permission: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        role_id?: string
        permission?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "role_permissions_role_id_fkey",
          columns: ["tenant_id", "role_id"],
          isOneToOne: false,
          referencedRelation: "tenant_roles",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    routing_operations: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        routing_id: string
        sequence?: number
        name: string
        description?: string
        work_center_id?: string
        machine_id?: string
        tooling_id?: string
        setup_time_min?: number
        run_time_min?: number
        is_subcontracted?: boolean
        supplier_id?: string
        st_unit?: string
        st_quantity?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        routing_id?: string
        sequence?: number
        name?: string
        description?: string
        work_center_id?: string
        machine_id?: string
        tooling_id?: string
        setup_time_min?: number
        run_time_min?: number
        is_subcontracted?: boolean
        supplier_id?: string
        st_unit?: string
        st_quantity?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "routing_operations_machine_id_fkey",
          columns: ["tenant_id", "machine_id"],
          isOneToOne: false,
          referencedRelation: "machines",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "routing_operations_routing_id_fkey",
          columns: ["tenant_id", "routing_id"],
          isOneToOne: false,
          referencedRelation: "routings",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "routing_operations_supplier_id_fkey",
          columns: ["tenant_id", "supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "routing_operations_tooling_id_fkey",
          columns: ["tenant_id", "tooling_id"],
          isOneToOne: false,
          referencedRelation: "toolings",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "routing_operations_work_center_id_fkey",
          columns: ["tenant_id", "work_center_id"],
          isOneToOne: false,
          referencedRelation: "work_centers",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    routings: {
      Row: {
        id: string
        tenant_id: string
        code: string
        name: string
        description: string | null
        product_id: string | null
        version: number | null
        active: boolean | null
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        code: string
        name: string
        description?: string
        product_id?: string
        version?: number
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        name?: string
        description?: string
        product_id?: string
        version?: number
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "routings_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    salary_advances: {
      Row: {
        id: string
        tenant_id: string
        employee_id: string
        amount: number
        advance_date: string
        deduction_month: string | null
        status: string | null
        notes: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        amount?: number
        advance_date?: string
        deduction_month?: string
        status?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        amount?: number
        advance_date?: string
        deduction_month?: string
        status?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "salary_advances_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
      Insert: {
        id?: string
        sales_order_id?: string
        product_id?: string
        description: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        line_total?: number
        tenant_id: string
        delivered_quantity?: number
      }
      Update: {
        id?: string
        sales_order_id?: string
        product_id?: string
        description?: string
        quantity?: number
        unit_price?: number
        vat_rate?: number
        line_total?: number
        tenant_id?: string
        delivered_quantity?: number
      }
      Relationships: [
        {
          foreignKeyName: "sales_order_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "sales_order_lines_sales_order_id_fkey",
          columns: ["tenant_id", "sales_order_id"],
          isOneToOne: false,
          referencedRelation: "sales_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "sales_order_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        credit_warning: boolean | null
      }
      Insert: {
        id?: string
        number: string
        customer_id?: string
        order_date?: string
        delivery_date?: string
        status?: string
        subtotal?: number
        vat?: number
        total?: number
        notes?: string
        created_at?: string
        updated_at?: string
        tenant_id: string
        validation_status?: string
        quote_id?: string
        fully_delivered?: boolean
        delivery_status?: string
        credit_warning?: boolean
      }
      Update: {
        id?: string
        number?: string
        customer_id?: string
        order_date?: string
        delivery_date?: string
        status?: string
        subtotal?: number
        vat?: number
        total?: number
        notes?: string
        created_at?: string
        updated_at?: string
        tenant_id?: string
        validation_status?: string
        quote_id?: string
        fully_delivered?: boolean
        delivery_status?: string
        credit_warning?: boolean
      }
      Relationships: [
        {
          foreignKeyName: "sales_orders_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "sales_orders_quote_id_fkey",
          columns: ["tenant_id", "quote_id"],
          isOneToOne: false,
          referencedRelation: "quotes",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "sales_orders_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    sales_representatives: {
      Row: {
        id: string
        tenant_id: string
        name: string
        email: string | null
        phone: string | null
        commission_rate: number | null
        territory: string | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        email?: string
        phone?: string
        commission_rate?: number
        territory?: string
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        email?: string
        phone?: string
        commission_rate?: number
        territory?: string
        active?: boolean
        created_at?: string
      }
      Relationships: [
      ]
    }
    saved_filters: {
      Row: {
        id: string
        tenant_id: string
        user_email: string
        page_name: string
        filter_name: string
        filter_criteria: Json
        is_default: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        user_email: string
        page_name: string
        filter_name: string
        filter_criteria?: Json
        is_default?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        user_email?: string
        page_name?: string
        filter_name?: string
        filter_criteria?: Json
        is_default?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "saved_filters_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    sepa_payment_orders: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        pay_run_id?: string
        number: string
        execution_date: string
        total_amount?: number
        currency?: string
        employee_count?: number
        file_url?: string
        file_generated_at?: string
        status?: string
        transmitted_at?: string
        processed_at?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        pay_run_id?: string
        number?: string
        execution_date?: string
        total_amount?: number
        currency?: string
        employee_count?: number
        file_url?: string
        file_generated_at?: string
        status?: string
        transmitted_at?: string
        processed_at?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "sepa_payment_orders_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "spo_pay_run_id_fkey",
          columns: ["tenant_id", "pay_run_id"],
          isOneToOne: false,
          referencedRelation: "pay_runs",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    service_contracts: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        number: string
        customer_id: string
        name: string
        contract_type?: string
        start_date: string
        end_date?: string
        status?: string
        sla_response_hours?: number
        sla_resolution_hours?: number
        coverage?: string
        max_tickets?: number
        used_tickets?: number
        amount?: number
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        number?: string
        customer_id?: string
        name?: string
        contract_type?: string
        start_date?: string
        end_date?: string
        status?: string
        sla_response_hours?: number
        sla_resolution_hours?: number
        coverage?: string
        max_tickets?: number
        used_tickets?: number
        amount?: number
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "service_contracts_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "service_contracts_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    service_ticket_messages: {
      Row: {
        id: string
        tenant_id: string
        ticket_id: string
        author: string
        author_type: string
        message: string
        attachments: Json | null
        is_internal: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        ticket_id: string
        author: string
        author_type: string
        message: string
        attachments?: Json
        is_internal?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        ticket_id?: string
        author?: string
        author_type?: string
        message?: string
        attachments?: Json
        is_internal?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "service_ticket_messages_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "service_ticket_messages_ticket_id_fkey",
          columns: ["tenant_id", "ticket_id"],
          isOneToOne: false,
          referencedRelation: "service_tickets",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    service_tickets: {
      Row: {
        id: string
        tenant_id: string
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
        tags: string[] | null
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        number: string
        customer_id: string
        contact_id?: string
        subject: string
        description?: string
        category?: string
        priority?: string
        status?: string
        assigned_to?: string
        sla_due_date?: string
        first_response_at?: string
        resolved_at?: string
        closed_at?: string
        satisfaction_rating?: number
        satisfaction_comment?: string
        tags?: string[]
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        number?: string
        customer_id?: string
        contact_id?: string
        subject?: string
        description?: string
        category?: string
        priority?: string
        status?: string
        assigned_to?: string
        sla_due_date?: string
        first_response_at?: string
        resolved_at?: string
        closed_at?: string
        satisfaction_rating?: number
        satisfaction_comment?: string
        tags?: string[]
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "service_tickets_contact_id_fkey",
          columns: ["tenant_id", "contact_id"],
          isOneToOne: false,
          referencedRelation: "customer_contacts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "service_tickets_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "service_tickets_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    sick_leaves: {
      Row: {
        id: string
        tenant_id: string
        employee_id: string
        leave_type: string
        start_date: string
        end_date: string
        waiting_days: number | null
        daily_ijss: number | null
        is_subrogated: boolean | null
        maintenance_rate: number | null
        medical_certificate_url: string | null
        status: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        leave_type: string
        start_date: string
        end_date: string
        waiting_days?: number
        daily_ijss?: number
        is_subrogated?: boolean
        maintenance_rate?: number
        medical_certificate_url?: string
        status?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        leave_type?: string
        start_date?: string
        end_date?: string
        waiting_days?: number
        daily_ijss?: number
        is_subrogated?: boolean
        maintenance_rate?: number
        medical_certificate_url?: string
        status?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "sick_leaves_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    social_declarations: {
      Row: {
        id: string
        tenant_id: string
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
        anomalies: Json | null
        amount: number | null
        employee_count: number | null
        details: Json | null
        notes: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        number: string
        declaration_type: string
        subtype?: string
        period_month?: number
        period_year?: number
        period?: string
        due_date?: string
        status?: string
        file_url?: string
        file_format?: string
        generated_at?: string
        transmitted_at?: string
        response_code?: string
        response_message?: string
        anomalies?: Json
        amount?: number
        employee_count?: number
        details?: Json
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        number?: string
        declaration_type?: string
        subtype?: string
        period_month?: number
        period_year?: number
        period?: string
        due_date?: string
        status?: string
        file_url?: string
        file_format?: string
        generated_at?: string
        transmitted_at?: string
        response_code?: string
        response_message?: string
        anomalies?: Json
        amount?: number
        employee_count?: number
        details?: Json
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "social_declarations_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    sql_migrations_tracker: {
      Row: {
        id: number
        filename: string
        executed_at: string | null
        status: string | null
        error_message: string | null
      }
      Insert: {
        id?: number
        filename: string
        executed_at?: string
        status?: string
        error_message?: string
      }
      Update: {
        id?: number
        filename?: string
        executed_at?: string
        status?: string
        error_message?: string
      }
      Relationships: [
      ]
    }
    st_orders: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        number: string
        supplier_id: string
        manufacturing_order_id?: string
        routing_operation_id?: string
        product_id?: string
        quantity?: number
        unit?: string
        unit_price?: number
        total_price?: number
        status?: string
        order_date?: string
        expected_date?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        number?: string
        supplier_id?: string
        manufacturing_order_id?: string
        routing_operation_id?: string
        product_id?: string
        quantity?: number
        unit?: string
        unit_price?: number
        total_price?: number
        status?: string
        order_date?: string
        expected_date?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "st_orders_manufacturing_order_id_fkey",
          columns: ["tenant_id", "manufacturing_order_id"],
          isOneToOne: false,
          referencedRelation: "manufacturing_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "st_orders_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "st_orders_routing_operation_id_fkey",
          columns: ["tenant_id", "routing_operation_id"],
          isOneToOne: false,
          referencedRelation: "routing_operations",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "st_orders_supplier_id_fkey",
          columns: ["tenant_id", "supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    st_receipt_lines: {
      Row: {
        id: string
        tenant_id: string
        st_receipt_id: string
        product_id: string
        quantity: number
        unit: string | null
        line_type: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        st_receipt_id: string
        product_id: string
        quantity?: number
        unit?: string
        line_type?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        st_receipt_id?: string
        product_id?: string
        quantity?: number
        unit?: string
        line_type?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "st_receipt_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "st_receipt_lines_st_receipt_id_fkey",
          columns: ["tenant_id", "st_receipt_id"],
          isOneToOne: false,
          referencedRelation: "st_receipts",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    st_receipts: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        number: string
        st_order_id: string
        receipt_date?: string
        warehouse_id?: string
        quantity_received?: number
        quantity_returned?: number
        status?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        number?: string
        st_order_id?: string
        receipt_date?: string
        warehouse_id?: string
        quantity_received?: number
        quantity_returned?: number
        status?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "st_receipts_st_order_id_fkey",
          columns: ["tenant_id", "st_order_id"],
          isOneToOne: false,
          referencedRelation: "st_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "st_receipts_warehouse_id_fkey",
          columns: ["tenant_id", "warehouse_id"],
          isOneToOne: false,
          referencedRelation: "warehouses",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    st_shipment_lines: {
      Row: {
        id: string
        tenant_id: string
        st_shipment_id: string
        product_id: string
        quantity: number
        unit: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        st_shipment_id: string
        product_id: string
        quantity?: number
        unit?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        st_shipment_id?: string
        product_id?: string
        quantity?: number
        unit?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "st_shipment_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "st_shipment_lines_st_shipment_id_fkey",
          columns: ["tenant_id", "st_shipment_id"],
          isOneToOne: false,
          referencedRelation: "st_shipments",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    st_shipments: {
      Row: {
        id: string
        tenant_id: string
        number: string
        st_order_id: string
        shipment_date: string
        warehouse_id: string | null
        status: string | null
        notes: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        number: string
        st_order_id: string
        shipment_date?: string
        warehouse_id?: string
        status?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        number?: string
        st_order_id?: string
        shipment_date?: string
        warehouse_id?: string
        status?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "st_shipments_st_order_id_fkey",
          columns: ["tenant_id", "st_order_id"],
          isOneToOne: false,
          referencedRelation: "st_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "st_shipments_warehouse_id_fkey",
          columns: ["tenant_id", "warehouse_id"],
          isOneToOne: false,
          referencedRelation: "warehouses",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    staff_requirements: {
      Row: {
        id: string
        tenant_id: string
        department: string
        min_staff: number
        days_of_week: string[] | null
        start_date: string | null
        end_date: string | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        department: string
        min_staff?: number
        days_of_week?: string[]
        start_date?: string
        end_date?: string
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        department?: string
        min_staff?: number
        days_of_week?: string[]
        start_date?: string
        end_date?: string
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "staff_requirements_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    standard_labels: {
      Row: {
        id: string
        label: string
        category: string | null
        created_at: string | null
        tenant_id: string
      }
      Insert: {
        id?: string
        label: string
        category?: string
        created_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        label?: string
        category?: string
        created_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "standard_labels_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    stat_fields: {
      Row: {
        id: string
        tenant_id: string
        entity_type: string
        entity_id: string
        field_name: string
        field_value: string | null
        field_type: string
        created_at: string
        updated_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        entity_type: string
        entity_id: string
        field_name: string
        field_value?: string
        field_type?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        entity_type?: string
        entity_id?: string
        field_name?: string
        field_value?: string
        field_type?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "stat_fields_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    stock_alerts: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        warehouse_id?: string
        alert_type: string
        threshold?: number
        current_value?: number
        status?: string
        triggered_at?: string
        resolved_at?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        warehouse_id?: string
        alert_type?: string
        threshold?: number
        current_value?: number
        status?: string
        triggered_at?: string
        resolved_at?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "stock_alerts_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "stock_alerts_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "stock_alerts_warehouse_id_fkey",
          columns: ["tenant_id", "warehouse_id"],
          isOneToOne: false,
          referencedRelation: "warehouses",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    stock_count_cycles: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        warehouse_id: string | null
        abc_class: string | null
        frequency_days: number
        last_count_date: string | null
        next_count_date: string | null
        is_active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        warehouse_id?: string
        abc_class?: string
        frequency_days?: number
        last_count_date?: string
        next_count_date?: string
        is_active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        warehouse_id?: string
        abc_class?: string
        frequency_days?: number
        last_count_date?: string
        next_count_date?: string
        is_active?: boolean
        created_at?: string
      }
      Relationships: [
      ]
    }
    stock_movement_phantoms: {
      Row: {
        id: string
        tenant_id: string
        movement_id: string
        product_id: string | null
        warehouse_id: string | null
        type: string
        quantity: number
        unit_cost: number | null
        movement_date: string | null
        reference: string | null
        detected_at: string
        decision: string
        decided_by: string | null
        decided_at: string | null
        replay_movement_id: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        movement_id: string
        product_id?: string
        warehouse_id?: string
        type: string
        quantity: number
        unit_cost?: number
        movement_date?: string
        reference?: string
        detected_at?: string
        decision?: string
        decided_by?: string
        decided_at?: string
        replay_movement_id?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        movement_id?: string
        product_id?: string
        warehouse_id?: string
        type?: string
        quantity?: number
        unit_cost?: number
        movement_date?: string
        reference?: string
        detected_at?: string
        decision?: string
        decided_by?: string
        decided_at?: string
        replay_movement_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "stock_movement_phantoms_movement_fkey",
          columns: ["tenant_id", "movement_id"],
          isOneToOne: false,
          referencedRelation: "stock_movements",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "stock_movement_phantoms_product_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "stock_movement_phantoms_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "stock_movement_phantoms_warehouse_fkey",
          columns: ["tenant_id", "warehouse_id"],
          isOneToOne: false,
          referencedRelation: "warehouses",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    stock_movements: {
      Row: {
        id: string
        product_id: string | null
        type: string
        quantity: number
        reference: string | null
        date: string
        created_at: string | null
        warehouse_id: string | null
        movement_type: string
        unit_cost: number | null
        reference_type: string | null
        reference_id: string | null
        movement_date: string | null
        notes: string | null
        tenant_id: string
        lot_id: string | null
        serial_id: string | null
        location_id: string | null
      }
      Insert: {
        id?: string
        product_id?: string
        type: string
        quantity?: number
        reference?: string
        date?: string
        created_at?: string
        warehouse_id?: string
        movement_type: string
        unit_cost?: number
        reference_type?: string
        reference_id?: string
        movement_date?: string
        notes?: string
        tenant_id: string
        lot_id?: string
        serial_id?: string
        location_id?: string
      }
      Update: {
        id?: string
        product_id?: string
        type?: string
        quantity?: number
        reference?: string
        date?: string
        created_at?: string
        warehouse_id?: string
        movement_type?: string
        unit_cost?: number
        reference_type?: string
        reference_id?: string
        movement_date?: string
        notes?: string
        tenant_id?: string
        lot_id?: string
        serial_id?: string
        location_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "sm_warehouse_id_fkey",
          columns: ["tenant_id", "warehouse_id"],
          isOneToOne: false,
          referencedRelation: "warehouses",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "stock_movements_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "stock_movements_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        quantity_available: number | null
      }
      Insert: {
        id?: string
        product_id: string
        warehouse_id: string
        quantity?: number
        reserved_quantity?: number
        min_quantity?: number
        max_quantity?: number
        reorder_point?: number
        unit_cost?: number
        created_at?: string
        updated_at?: string
        tenant_id: string
        location_id?: string
        incoming_quantity?: number
        quantity_available?: number
      }
      Update: {
        id?: string
        product_id?: string
        warehouse_id?: string
        quantity?: number
        reserved_quantity?: number
        min_quantity?: number
        max_quantity?: number
        reorder_point?: number
        unit_cost?: number
        created_at?: string
        updated_at?: string
        tenant_id?: string
        location_id?: string
        incoming_quantity?: number
        quantity_available?: number
      }
      Relationships: [
        {
          foreignKeyName: "stock_quantities_location_id_fkey",
          columns: ["tenant_id", "location_id"],
          isOneToOne: false,
          referencedRelation: "warehouse_locations",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "stock_quantities_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "stock_quantities_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "stock_quantities_warehouse_id_fkey",
          columns: ["tenant_id", "warehouse_id"],
          isOneToOne: false,
          referencedRelation: "warehouses",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    stock_reservations: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        warehouse_id: string | null
        quantity: number
        reserved_by: string
        reference_id: string | null
        reference_type: string
        status: string
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        warehouse_id?: string
        quantity: number
        reserved_by?: string
        reference_id?: string
        reference_type?: string
        status?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        warehouse_id?: string
        quantity?: number
        reserved_by?: string
        reference_id?: string
        reference_type?: string
        status?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "stock_reservations_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "stock_reservations_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "stock_reservations_warehouse_id_fkey",
          columns: ["tenant_id", "warehouse_id"],
          isOneToOne: false,
          referencedRelation: "warehouses",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    stock_transfer_lines: {
      Row: {
        id: string
        tenant_id: string
        transfer_id: string
        product_id: string
        quantity: number
        unit_cost: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        transfer_id: string
        product_id: string
        quantity: number
        unit_cost?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        transfer_id?: string
        product_id?: string
        quantity?: number
        unit_cost?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "stock_transfer_lines_transfer_id_fkey",
          columns: ["tenant_id", "transfer_id"],
          isOneToOne: false,
          referencedRelation: "stock_transfers",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    stock_transfers: {
      Row: {
        id: string
        tenant_id: string
        transfer_number: string
        from_warehouse_id: string
        to_warehouse_id: string
        shipment_date: string | null
        expected_receipt_date: string | null
        actual_receipt_date: string | null
        status: string | null
        notes: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        transfer_number: string
        from_warehouse_id: string
        to_warehouse_id: string
        shipment_date?: string
        expected_receipt_date?: string
        actual_receipt_date?: string
        status?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        transfer_number?: string
        from_warehouse_id?: string
        to_warehouse_id?: string
        shipment_date?: string
        expected_receipt_date?: string
        actual_receipt_date?: string
        status?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
      ]
    }
    stock_valuation_layers: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        warehouse_id: string | null
        movement_id: string
        quantity: number
        remaining_qty: number
        unit_cost: number
        value: number
        created_at: string | null
        seq: number
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        warehouse_id?: string
        movement_id: string
        quantity: number
        remaining_qty: number
        unit_cost: number
        value: number
        created_at?: string
        seq?: number
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        warehouse_id?: string
        movement_id?: string
        quantity?: number
        remaining_qty?: number
        unit_cost?: number
        value?: number
        created_at?: string
        seq?: number
      }
      Relationships: [
      ]
    }
    supplier_contacts: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        supplier_id: string
        name: string
        role?: string
        email?: string
        phone?: string
        mobile?: string
        is_default?: boolean
        active?: boolean
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        supplier_id?: string
        name?: string
        role?: string
        email?: string
        phone?: string
        mobile?: string
        is_default?: boolean
        active?: boolean
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "supplier_contacts_supplier_id_fkey",
          columns: ["tenant_id", "supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "supplier_contacts_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    supplier_delivery_schedules: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        supplier_id: string
        product_id: string
        warehouse_id?: string
        frequency: string
        monday_qty?: number
        tuesday_qty?: number
        wednesday_qty?: number
        thursday_qty?: number
        friday_qty?: number
        saturday_qty?: number
        sunday_qty?: number
        start_date?: string
        end_date?: string
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        supplier_id?: string
        product_id?: string
        warehouse_id?: string
        frequency?: string
        monday_qty?: number
        tuesday_qty?: number
        wednesday_qty?: number
        thursday_qty?: number
        friday_qty?: number
        saturday_qty?: number
        sunday_qty?: number
        start_date?: string
        end_date?: string
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "supplier_delivery_schedules_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "supplier_delivery_schedules_supplier_id_fkey",
          columns: ["tenant_id", "supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "supplier_delivery_schedules_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "supplier_delivery_schedules_warehouse_id_fkey",
          columns: ["tenant_id", "warehouse_id"],
          isOneToOne: false,
          referencedRelation: "warehouses",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
        invoice_number: string | null
      }
      Insert: {
        id?: string
        number: string
        supplier_id?: string
        purchase_invoice_id?: string
        payment_date?: string
        amount?: number
        method?: string
        bank_account_id?: string
        reference?: string
        status?: string
        created_at?: string
        tenant_id: string
        currency_code?: string
        exchange_rate?: number
        amount_currency?: number
        exchange_gain_loss?: number
        transferred_entry_id?: string
        invoice_number?: string
      }
      Update: {
        id?: string
        number?: string
        supplier_id?: string
        purchase_invoice_id?: string
        payment_date?: string
        amount?: number
        method?: string
        bank_account_id?: string
        reference?: string
        status?: string
        created_at?: string
        tenant_id?: string
        currency_code?: string
        exchange_rate?: number
        amount_currency?: number
        exchange_gain_loss?: number
        transferred_entry_id?: string
        invoice_number?: string
      }
      Relationships: [
        {
          foreignKeyName: "supplier_payments_bank_account_id_fkey",
          columns: ["tenant_id", "bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "supplier_payments_purchase_invoice_id_fkey",
          columns: ["tenant_id", "purchase_invoice_id"],
          isOneToOne: false,
          referencedRelation: "purchase_invoices",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "supplier_payments_supplier_id_fkey",
          columns: ["tenant_id", "supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "supplier_payments_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "supplier_payments_transferred_entry_id_fkey",
          columns: ["tenant_id", "transferred_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    supplier_price_list_lines: {
      Row: {
        id: string
        tenant_id: string
        price_list_id: string
        product_id: string
        supplier_ref: string | null
        unit_price: number
        min_quantity: number | null
        discount_percent: number | null
        lead_time_days: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        price_list_id: string
        product_id: string
        supplier_ref?: string
        unit_price: number
        min_quantity?: number
        discount_percent?: number
        lead_time_days?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        price_list_id?: string
        product_id?: string
        supplier_ref?: string
        unit_price?: number
        min_quantity?: number
        discount_percent?: number
        lead_time_days?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "supplier_price_list_lines_price_list_id_fkey",
          columns: ["tenant_id", "price_list_id"],
          isOneToOne: false,
          referencedRelation: "supplier_price_lists",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "supplier_price_list_lines_product_id_fkey",
          columns: ["tenant_id", "product_id"],
          isOneToOne: false,
          referencedRelation: "products",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "supplier_price_list_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    supplier_price_lists: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        supplier_id: string
        name: string
        valid_from?: string
        valid_to?: string
        currency_code?: string
        min_quantity?: number
        discount_percent?: number
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        supplier_id?: string
        name?: string
        valid_from?: string
        valid_to?: string
        currency_code?: string
        min_quantity?: number
        discount_percent?: number
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "supplier_price_lists_supplier_id_fkey",
          columns: ["tenant_id", "supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "supplier_price_lists_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        email_settings: Json | null
        account_tiers: string | null
        account_collectif: string | null
        import_batch_id: string | null
        payment_term_id: string | null
        fiscal_position_id: string | null
      }
      Insert: {
        id?: string
        name: string
        email?: string
        phone?: string
        address?: string
        city?: string
        postal_code?: string
        country?: string
        vat_number?: string
        contact_name?: string
        balance?: number
        payment_terms?: string
        currency?: string
        active?: boolean
        created_at?: string
        updated_at?: string
        tenant_id: string
        legal_form?: string
        ape_code?: string
        naf_code?: string
        employee_count_range?: string
        revenue_range?: string
        payment_delay_avg?: number
        siret?: string
        sector_code?: string
        geographic_zone?: string
        parent_id?: string
        is_company?: boolean
        sales_rep_id?: string
        currency_code?: string
        bank_account_id?: string
        price_list_id?: string
        email_settings?: Json
        account_tiers?: string
        account_collectif?: string
        import_batch_id?: string
        payment_term_id?: string
        fiscal_position_id?: string
      }
      Update: {
        id?: string
        name?: string
        email?: string
        phone?: string
        address?: string
        city?: string
        postal_code?: string
        country?: string
        vat_number?: string
        contact_name?: string
        balance?: number
        payment_terms?: string
        currency?: string
        active?: boolean
        created_at?: string
        updated_at?: string
        tenant_id?: string
        legal_form?: string
        ape_code?: string
        naf_code?: string
        employee_count_range?: string
        revenue_range?: string
        payment_delay_avg?: number
        siret?: string
        sector_code?: string
        geographic_zone?: string
        parent_id?: string
        is_company?: boolean
        sales_rep_id?: string
        currency_code?: string
        bank_account_id?: string
        price_list_id?: string
        email_settings?: Json
        account_tiers?: string
        account_collectif?: string
        import_batch_id?: string
        payment_term_id?: string
        fiscal_position_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "suppliers_bank_account_id_fkey",
          columns: ["tenant_id", "bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "suppliers_fiscal_position_tenant_fkey",
          columns: ["tenant_id", "fiscal_position_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_positions",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "suppliers_parent_id_fkey",
          columns: ["tenant_id", "parent_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "suppliers_payment_term_tenant_fkey",
          columns: ["tenant_id", "payment_term_id"],
          isOneToOne: false,
          referencedRelation: "payment_terms",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "suppliers_price_list_id_fkey",
          columns: ["tenant_id", "price_list_id"],
          isOneToOne: false,
          referencedRelation: "price_lists",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "suppliers_sales_rep_id_fkey",
          columns: ["tenant_id", "sales_rep_id"],
          isOneToOne: false,
          referencedRelation: "sales_representatives",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "suppliers_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    task_action_attachments: {
      Row: {
        id: string
        tenant_id: string
        task_action_id: string
        task_id: string
        file_name: string
        file_path: string
        file_size: number | null
        mime_type: string | null
        uploader_id: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        task_action_id: string
        task_id: string
        file_name: string
        file_path: string
        file_size?: number
        mime_type?: string
        uploader_id?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        task_action_id?: string
        task_id?: string
        file_name?: string
        file_path?: string
        file_size?: number
        mime_type?: string
        uploader_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "task_action_attachments_task_action_id_fkey",
          columns: ["tenant_id", "task_action_id"],
          isOneToOne: false,
          referencedRelation: "task_actions",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "task_action_attachments_task_id_fkey",
          columns: ["tenant_id", "task_id"],
          isOneToOne: false,
          referencedRelation: "project_tasks",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "task_action_attachments_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id: string
        task_id: string
        title: string
        weight_percentage?: number
        is_done?: boolean
        due_date?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        task_id?: string
        title?: string
        weight_percentage?: number
        is_done?: boolean
        due_date?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "task_actions_task_id_fkey",
          columns: ["tenant_id", "task_id"],
          isOneToOne: false,
          referencedRelation: "project_tasks",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "task_actions_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
      Insert: {
        id?: string
        tenant_id: string
        task_id: string
        content: string
        comment_type?: string
        author_id?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        task_id?: string
        content?: string
        comment_type?: string
        author_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "task_comments_task_id_fkey",
          columns: ["tenant_id", "task_id"],
          isOneToOne: false,
          referencedRelation: "project_tasks",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "task_comments_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    task_documents: {
      Row: {
        id: string
        tenant_id: string
        task_id: string
        project_id: string | null
        file_name: string
        file_path: string
        file_size: number | null
        mime_type: string | null
        uploader_id: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        task_id: string
        project_id?: string
        file_name: string
        file_path: string
        file_size?: number
        mime_type?: string
        uploader_id?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        task_id?: string
        project_id?: string
        file_name?: string
        file_path?: string
        file_size?: number
        mime_type?: string
        uploader_id?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "task_documents_project_id_fkey",
          columns: ["tenant_id", "project_id"],
          isOneToOne: false,
          referencedRelation: "projects",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "task_documents_task_id_fkey",
          columns: ["tenant_id", "task_id"],
          isOneToOne: false,
          referencedRelation: "project_tasks",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "task_documents_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    tax_cash_basis_entries: {
      Row: {
        id: string
        tenant_id: string
        tax_id: string | null
        payment_id: string | null
        journal_entry_id: string | null
        base_amount: number | null
        tax_amount: number | null
        transition_date: string | null
        status: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        tax_id?: string
        payment_id?: string
        journal_entry_id?: string
        base_amount?: number
        tax_amount?: number
        transition_date?: string
        status?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        tax_id?: string
        payment_id?: string
        journal_entry_id?: string
        base_amount?: number
        tax_amount?: number
        transition_date?: string
        status?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "tax_cash_basis_entries_tax_id_fkey",
          columns: ["tenant_id", "tax_id"],
          isOneToOne: false,
          referencedRelation: "tax_rates",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "tax_cash_basis_entries_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "tcb_journal_entry_id_fkey",
          columns: ["tenant_id", "journal_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    tax_groups: {
      Row: {
        id: string
        tenant_id: string
        name: string
        country_code: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        country_code?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        country_code?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "tax_groups_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    tax_payments: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        payment_number: string
        tax_type: string
        period_label: string
        period_start: string
        period_end: string
        amount?: number
        payment_date: string
        payment_method?: string
        bank_account_id?: string
        status?: string
        confirmation_number?: string
        journal_entry_id?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        payment_number?: string
        tax_type?: string
        period_label?: string
        period_start?: string
        period_end?: string
        amount?: number
        payment_date?: string
        payment_method?: string
        bank_account_id?: string
        status?: string
        confirmation_number?: string
        journal_entry_id?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "tax_payments_bank_account_id_fkey",
          columns: ["tenant_id", "bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "tax_payments_journal_entry_id_fkey",
          columns: ["tenant_id", "journal_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "tax_payments_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        tenant_id: string
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
      Insert: {
        id?: string
        pack_code: string
        name: string
        category: string
        rate: number
        account_code?: string
        is_default?: boolean
        effective_from?: string
        effective_to?: string
        created_at?: string
        tenant_id: string
        account_collectee?: string
        account_deductible?: string
        type?: string
        mode?: string
        amount_type?: string
        type_tax_use?: string
        sequence?: number
        parent_tax_id?: string
        tax_exigibility?: string
        cash_basis_transition_account?: string
        price_include?: boolean
        include_base_amount?: boolean
        is_base_affected?: boolean
        analytic?: boolean
        fixed_amount?: number
      }
      Update: {
        id?: string
        pack_code?: string
        name?: string
        category?: string
        rate?: number
        account_code?: string
        is_default?: boolean
        effective_from?: string
        effective_to?: string
        created_at?: string
        tenant_id?: string
        account_collectee?: string
        account_deductible?: string
        type?: string
        mode?: string
        amount_type?: string
        type_tax_use?: string
        sequence?: number
        parent_tax_id?: string
        tax_exigibility?: string
        cash_basis_transition_account?: string
        price_include?: boolean
        include_base_amount?: boolean
        is_base_affected?: boolean
        analytic?: boolean
        fixed_amount?: number
      }
      Relationships: [
        {
          foreignKeyName: "tax_rates_pack_code_fkey",
          columns: ["pack_code"],
          isOneToOne: true,
          referencedRelation: "legislation_packs",
          referencedColumns: ["code"]
        },
        {
          foreignKeyName: "tax_rates_parent_tax_id_fkey",
          columns: ["tenant_id", "parent_tax_id"],
          isOneToOne: false,
          referencedRelation: "tax_rates",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "tax_rates_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    tax_repartition_lines: {
      Row: {
        id: string
        tenant_id: string
        tax_id: string
        document_type: string
        repartition_type: string
        factor: number | null
        account_code: string | null
        tag_ids: string[] | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        tax_id: string
        document_type: string
        repartition_type: string
        factor?: number
        account_code?: string
        tag_ids?: string[]
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        tax_id?: string
        document_type?: string
        repartition_type?: string
        factor?: number
        account_code?: string
        tag_ids?: string[]
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "tax_repartition_lines_tax_id_fkey",
          columns: ["tenant_id", "tax_id"],
          isOneToOne: false,
          referencedRelation: "tax_rates",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "tax_repartition_lines_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    tenant_onboarding_state: {
      Row: {
        id: string
        tenant_id: string
        step_identity: boolean | null
        step_legislation: boolean | null
        step_fiscal_year: boolean | null
        step_chart_accounts: boolean | null
        step_journals: boolean | null
        step_default_accounts: boolean | null
        step_vat_rates: boolean | null
        step_payment_methods: boolean | null
        step_stock_valuation: boolean | null
        step_users: boolean | null
        completed: boolean | null
        completed_at: string | null
        created_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        step_identity?: boolean
        step_legislation?: boolean
        step_fiscal_year?: boolean
        step_chart_accounts?: boolean
        step_journals?: boolean
        step_default_accounts?: boolean
        step_vat_rates?: boolean
        step_payment_methods?: boolean
        step_stock_valuation?: boolean
        step_users?: boolean
        completed?: boolean
        completed_at?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        step_identity?: boolean
        step_legislation?: boolean
        step_fiscal_year?: boolean
        step_chart_accounts?: boolean
        step_journals?: boolean
        step_default_accounts?: boolean
        step_vat_rates?: boolean
        step_payment_methods?: boolean
        step_stock_valuation?: boolean
        step_users?: boolean
        completed?: boolean
        completed_at?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
      ]
    }
    tenant_roles: {
      Row: {
        id: string
        tenant_id: string
        name: string
        description: string | null
        is_system: boolean | null
        is_active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        description?: string
        is_system?: boolean
        is_active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        description?: string
        is_system?: boolean
        is_active?: boolean
        created_at?: string
      }
      Relationships: [
      ]
    }
    tenant_users: {
      Row: {
        id: string
        tenant_id: string
        auth_id: string | null
        email: string
        name: string
        role: string
        permissions: Json | null
        status: string
        invited_by: string | null
        invited_at: string | null
        accepted_at: string | null
        last_login: string | null
        created_at: string | null
        updated_at: string | null
        valid_from: string | null
        valid_until: string | null
        module_roles: Json | null
        guest_permissions: Json | null
        custom_role_id: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        auth_id?: string
        email: string
        name: string
        role?: string
        permissions?: Json
        status?: string
        invited_by?: string
        invited_at?: string
        accepted_at?: string
        last_login?: string
        created_at?: string
        updated_at?: string
        valid_from?: string
        valid_until?: string
        module_roles?: Json
        guest_permissions?: Json
        custom_role_id?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        auth_id?: string
        email?: string
        name?: string
        role?: string
        permissions?: Json
        status?: string
        invited_by?: string
        invited_at?: string
        accepted_at?: string
        last_login?: string
        created_at?: string
        updated_at?: string
        valid_from?: string
        valid_until?: string
        module_roles?: Json
        guest_permissions?: Json
        custom_role_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "tenant_users_auth_id_fkey",
          columns: ["auth_id"],
          isOneToOne: false,
          referencedRelation: "users",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "tenant_users_custom_role_id_fkey",
          columns: ["tenant_id", "custom_role_id"],
          isOneToOne: false,
          referencedRelation: "tenant_roles",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "tenant_users_invited_by_fkey",
          columns: ["tenant_id", "invited_by"],
          isOneToOne: false,
          referencedRelation: "tenant_users",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "tenant_users_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        enabled_modules: Json
        chart_pack_code: string | null
        chart_provisional: boolean
      }
      Insert: {
        id?: string
        name: string
        legal_name?: string
        siren?: string
        siret?: string
        vat_number?: string
        address?: string
        city?: string
        postal_code?: string
        country?: string
        currency?: string
        phone?: string
        email?: string
        logo_url?: string
        status?: string
        plan?: string
        trial_ends_at?: string
        created_at?: string
        updated_at?: string
        country_code?: string
        legislation_pack_code?: string
        enabled_modules?: Json
        chart_pack_code?: string
        chart_provisional?: boolean
      }
      Update: {
        id?: string
        name?: string
        legal_name?: string
        siren?: string
        siret?: string
        vat_number?: string
        address?: string
        city?: string
        postal_code?: string
        country?: string
        currency?: string
        phone?: string
        email?: string
        logo_url?: string
        status?: string
        plan?: string
        trial_ends_at?: string
        created_at?: string
        updated_at?: string
        country_code?: string
        legislation_pack_code?: string
        enabled_modules?: Json
        chart_pack_code?: string
        chart_provisional?: boolean
      }
      Relationships: [
        {
          foreignKeyName: "tenants_chart_pack_code_fkey",
          columns: ["chart_pack_code"],
          isOneToOne: false,
          referencedRelation: "legislation_packs",
          referencedColumns: ["code"]
        },
        {
          foreignKeyName: "tenants_legislation_pack_code_fkey",
          columns: ["legislation_pack_code"],
          isOneToOne: false,
          referencedRelation: "legislation_packs",
          referencedColumns: ["code"]
        },
      ]
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
      Insert: {
        id?: string
        code: string
        account_general_code?: string
        type: string
        name: string
        customer_id?: string
        supplier_id?: string
        employee_id?: string
        balance?: number
        lettrage_code?: string
        currency?: string
        active?: boolean
        created_at?: string
        updated_at?: string
        tenant_id: string
        payment_term_id?: string
        default_bank_account_id?: string
        credit_limit?: number
      }
      Update: {
        id?: string
        code?: string
        account_general_code?: string
        type?: string
        name?: string
        customer_id?: string
        supplier_id?: string
        employee_id?: string
        balance?: number
        lettrage_code?: string
        currency?: string
        active?: boolean
        created_at?: string
        updated_at?: string
        tenant_id?: string
        payment_term_id?: string
        default_bank_account_id?: string
        credit_limit?: number
      }
      Relationships: [
        {
          foreignKeyName: "fk_tpa_payment_term",
          columns: ["tenant_id", "payment_term_id"],
          isOneToOne: false,
          referencedRelation: "payment_terms",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "third_party_accounts_customer_id_fkey",
          columns: ["tenant_id", "customer_id"],
          isOneToOne: false,
          referencedRelation: "customers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "third_party_accounts_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "users",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "third_party_accounts_supplier_id_fkey",
          columns: ["tenant_id", "supplier_id"],
          isOneToOne: false,
          referencedRelation: "suppliers",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "third_party_accounts_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "tpa_default_bank_account_id_fkey",
          columns: ["tenant_id", "default_bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    three_way_matches: {
      Row: {
        id: string
        tenant_id: string
        purchase_order_id: string | null
        goods_receipt_id: string | null
        purchase_invoice_id: string | null
        match_status: string
        total_ordered: number | null
        total_received: number | null
        total_invoiced: number | null
        price_variance: number | null
        quantity_variance: number | null
        line_results: Json | null
        checked_at: string | null
        checked_by: string | null
        notes: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        purchase_order_id?: string
        goods_receipt_id?: string
        purchase_invoice_id?: string
        match_status?: string
        total_ordered?: number
        total_received?: number
        total_invoiced?: number
        price_variance?: number
        quantity_variance?: number
        line_results?: Json
        checked_at?: string
        checked_by?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        purchase_order_id?: string
        goods_receipt_id?: string
        purchase_invoice_id?: string
        match_status?: string
        total_ordered?: number
        total_received?: number
        total_invoiced?: number
        price_variance?: number
        quantity_variance?: number
        line_results?: Json
        checked_at?: string
        checked_by?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "three_way_matches_goods_receipt_id_fkey",
          columns: ["tenant_id", "goods_receipt_id"],
          isOneToOne: false,
          referencedRelation: "goods_receipts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "three_way_matches_purchase_invoice_id_fkey",
          columns: ["tenant_id", "purchase_invoice_id"],
          isOneToOne: false,
          referencedRelation: "purchase_invoices",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "three_way_matches_purchase_order_id_fkey",
          columns: ["tenant_id", "purchase_order_id"],
          isOneToOne: false,
          referencedRelation: "purchase_orders",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "three_way_matches_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    tier_ribs: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        third_party_account_id: string
        rib_label: string
        iban: string
        bic?: string
        bank_name?: string
        bank_code?: string
        branch_code?: string
        account_number?: string
        key?: string
        is_default?: boolean
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        third_party_account_id?: string
        rib_label?: string
        iban?: string
        bic?: string
        bank_name?: string
        bank_code?: string
        branch_code?: string
        account_number?: string
        key?: string
        is_default?: boolean
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "tier_ribs_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "tier_ribs_third_party_account_id_fkey",
          columns: ["tenant_id", "third_party_account_id"],
          isOneToOne: false,
          referencedRelation: "third_party_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
        arrival_time: string | null
        departure_time: string | null
        scheduled_start: string | null
        scheduled_end: string | null
        late_minutes: number | null
        late_justified: boolean | null
        late_justification: string | null
        early_leave_minutes: number | null
        overtime_minutes: number | null
        absence_type: string | null
        absence_reason: string | null
        shift_date: string | null
        approved_by: string | null
        approved_at: string | null
      }
      Insert: {
        id?: string
        employee_id?: string
        date?: string
        hours?: number
        description?: string
        project_id?: string
        status?: string
        created_at?: string
        tenant_id: string
        arrival_time?: string
        departure_time?: string
        scheduled_start?: string
        scheduled_end?: string
        late_minutes?: number
        late_justified?: boolean
        late_justification?: string
        early_leave_minutes?: number
        overtime_minutes?: number
        absence_type?: string
        absence_reason?: string
        shift_date?: string
        approved_by?: string
        approved_at?: string
      }
      Update: {
        id?: string
        employee_id?: string
        date?: string
        hours?: number
        description?: string
        project_id?: string
        status?: string
        created_at?: string
        tenant_id?: string
        arrival_time?: string
        departure_time?: string
        scheduled_start?: string
        scheduled_end?: string
        late_minutes?: number
        late_justified?: boolean
        late_justification?: string
        early_leave_minutes?: number
        overtime_minutes?: number
        absence_type?: string
        absence_reason?: string
        shift_date?: string
        approved_by?: string
        approved_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "timesheets_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "timesheets_project_id_fkey",
          columns: ["tenant_id", "project_id"],
          isOneToOne: false,
          referencedRelation: "projects",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "timesheets_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    toolings: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        code: string
        name: string
        machine_id?: string
        max_pieces?: number
        initial_counter?: number
        current_counter?: number
        status?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        name?: string
        machine_id?: string
        max_pieces?: number
        initial_counter?: number
        current_counter?: number
        status?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "toolings_machine_id_fkey",
          columns: ["tenant_id", "machine_id"],
          isOneToOne: false,
          referencedRelation: "machines",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    tracking_warnings: {
      Row: {
        id: string
        tenant_id: string
        product_id: string
        movement_id: string | null
        warning_type: string
        message: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        product_id: string
        movement_id?: string
        warning_type: string
        message?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        product_id?: string
        movement_id?: string
        warning_type?: string
        message?: string
        created_at?: string
      }
      Relationships: [
      ]
    }
    treasury_recurring: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        description: string
        bank_account_id?: string
        amount?: number
        type: string
        frequency?: string
        next_date?: string
        end_date?: string
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        description?: string
        bank_account_id?: string
        amount?: number
        type?: string
        frequency?: string
        next_date?: string
        end_date?: string
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "treasury_recurring_bank_account_id_fkey",
          columns: ["tenant_id", "bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    treasury_transfers: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        number: string
        from_account_id: string
        to_account_id: string
        amount?: number
        transfer_date?: string
        value_date?: string
        status?: string
        journal_entry_id?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        number?: string
        from_account_id?: string
        to_account_id?: string
        amount?: number
        transfer_date?: string
        value_date?: string
        status?: string
        journal_entry_id?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "treasury_transfers_from_account_id_fkey",
          columns: ["tenant_id", "from_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "treasury_transfers_to_account_id_fkey",
          columns: ["tenant_id", "to_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "tt_journal_entry_id_fkey",
          columns: ["tenant_id", "journal_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    tvs_declarations: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        fiscal_year: number
        vehicle_registration: string
        vehicle_type?: string
        co2_emissions?: number
        first_registration_date?: string
        amount_co2?: number
        amount_age?: number
        amount_total?: number
        status?: string
        filed_at?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        fiscal_year?: number
        vehicle_registration?: string
        vehicle_type?: string
        co2_emissions?: number
        first_registration_date?: string
        amount_co2?: number
        amount_age?: number
        amount_total?: number
        status?: string
        filed_at?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "tvs_declarations_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    uom_categories: {
      Row: {
        id: string
        tenant_id: string
        name: string
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        created_at?: string
      }
      Relationships: [
      ]
    }
    uoms: {
      Row: {
        id: string
        tenant_id: string
        code: string
        name: string
        category_id: string
        factor: number
        is_base: boolean | null
        rounding: number | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        code: string
        name: string
        category_id: string
        factor?: number
        is_base?: boolean
        rounding?: number
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        name?: string
        category_id?: string
        factor?: number
        is_base?: boolean
        rounding?: number
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "uoms_category_id_fkey",
          columns: ["tenant_id", "category_id"],
          isOneToOne: false,
          referencedRelation: "uom_categories",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    user_totp: {
      Row: {
        id: string
        user_id: string
        tenant_id: string
        secret_enc: string
        backup_codes: Json
        enabled: boolean
        enabled_at: string | null
        created_at: string
      }
      Insert: {
        id?: string
        user_id: string
        tenant_id: string
        secret_enc: string
        backup_codes?: Json
        enabled?: boolean
        enabled_at?: string
        created_at?: string
      }
      Update: {
        id?: string
        user_id?: string
        tenant_id?: string
        secret_enc?: string
        backup_codes?: Json
        enabled?: boolean
        enabled_at?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "user_totp_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
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
        tenant_id: string
      }
      Insert: {
        id?: string
        auth_id?: string
        name: string
        email: string
        role?: string
        active?: boolean
        last_login?: string
        created_at?: string
        updated_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        auth_id?: string
        name?: string
        email?: string
        role?: string
        active?: boolean
        last_login?: string
        created_at?: string
        updated_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "users_auth_id_fkey",
          columns: ["auth_id"],
          isOneToOne: false,
          referencedRelation: "users",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "users_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    v_tenant_id: {
      Row: {
        id: string | null
      }
      Insert: {
        id?: string
      }
      Update: {
        id?: string
      }
      Relationships: [
      ]
    }
    value_date_tracking: {
      Row: {
        id: string
        tenant_id: string
        bank_account_id: string
        transaction_id: string | null
        operation_date: string
        value_date: string
        amount: number
        transaction_type: string | null
        notes: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        bank_account_id: string
        transaction_id?: string
        operation_date: string
        value_date: string
        amount?: number
        transaction_type?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        bank_account_id?: string
        transaction_id?: string
        operation_date?: string
        value_date?: string
        amount?: number
        transaction_type?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "value_date_tracking_bank_account_id_fkey",
          columns: ["tenant_id", "bank_account_id"],
          isOneToOne: false,
          referencedRelation: "bank_accounts",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    vat_account_mapping: {
      Row: {
        id: string
        tenant_id: string
        vat_code: string
        rate: number
        direction: string
        account_code: string
        ca3_box: string | null
        base_account: string | null
        reverse_charge: boolean
        account_name: string | null
        label: string | null
        ca3_base_box: string | null
        ca3_tax_box: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        vat_code: string
        rate: number
        direction: string
        account_code: string
        ca3_box?: string
        base_account?: string
        reverse_charge?: boolean
        account_name?: string
        label?: string
        ca3_base_box?: string
        ca3_tax_box?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        vat_code?: string
        rate?: number
        direction?: string
        account_code?: string
        ca3_box?: string
        base_account?: string
        reverse_charge?: boolean
        account_name?: string
        label?: string
        ca3_base_box?: string
        ca3_tax_box?: string
      }
      Relationships: [
      ]
    }
    vat_on_collections: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        fiscal_year_id?: string
        period_label: string
        period_start: string
        period_end: string
        vat_base?: number
        vat_rate?: number
        vat_amount?: number
        collected_amount?: number
        uncollected_amount?: number
        vat_collected?: number
        vat_uncollected?: number
        status?: string
        journal_entry_id?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        fiscal_year_id?: string
        period_label?: string
        period_start?: string
        period_end?: string
        vat_base?: number
        vat_rate?: number
        vat_amount?: number
        collected_amount?: number
        uncollected_amount?: number
        vat_collected?: number
        vat_uncollected?: number
        status?: string
        journal_entry_id?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "vat_on_collections_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "voc_fiscal_year_id_fkey",
          columns: ["tenant_id", "fiscal_year_id"],
          isOneToOne: false,
          referencedRelation: "fiscal_years",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "voc_journal_entry_id_fkey",
          columns: ["tenant_id", "journal_entry_id"],
          isOneToOne: false,
          referencedRelation: "journal_entries",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
        vat_collected: number | null
        vat_deductible: number | null
        vat_to_pay: number | null
      }
      Insert: {
        id?: string
        period_start: string
        period_end: string
        status?: string
        box1_output_vat?: number
        box2_input_vat?: number
        box3_vat_due?: number
        box4_repayment_due?: number
        box5_net_vat?: number
        total_sales?: number
        total_purchases?: number
        submitted_date?: string
        created_at?: string
        tenant_id: string
        edi_tva_id?: string
        edi_status?: string
        edi_submitted_at?: string
        edi_acknowledgment?: string
        edi_acknowledged_at?: string
        deposits_vat_collected?: number
        deposits_vat_deductible?: number
        vat_collected?: number
        vat_deductible?: number
        vat_to_pay?: number
      }
      Update: {
        id?: string
        period_start?: string
        period_end?: string
        status?: string
        box1_output_vat?: number
        box2_input_vat?: number
        box3_vat_due?: number
        box4_repayment_due?: number
        box5_net_vat?: number
        total_sales?: number
        total_purchases?: number
        submitted_date?: string
        created_at?: string
        tenant_id?: string
        edi_tva_id?: string
        edi_status?: string
        edi_submitted_at?: string
        edi_acknowledgment?: string
        edi_acknowledged_at?: string
        deposits_vat_collected?: number
        deposits_vat_deductible?: number
        vat_collected?: number
        vat_deductible?: number
        vat_to_pay?: number
      }
      Relationships: [
        {
          foreignKeyName: "vat_returns_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    warehouse_locations: {
      Row: {
        id: string
        tenant_id: string
        warehouse_id: string
        zone: string | null
        aisle: string | null
        shelf: string | null
        code: string
        description: string | null
        created_at: string | null
        parent_id: string | null
        location_type: string | null
        max_weight: number | null
        max_volume: number | null
        max_pallets: number | null
      }
      Insert: {
        id?: string
        tenant_id: string
        warehouse_id: string
        zone?: string
        aisle?: string
        shelf?: string
        code: string
        description?: string
        created_at?: string
        parent_id?: string
        location_type?: string
        max_weight?: number
        max_volume?: number
        max_pallets?: number
      }
      Update: {
        id?: string
        tenant_id?: string
        warehouse_id?: string
        zone?: string
        aisle?: string
        shelf?: string
        code?: string
        description?: string
        created_at?: string
        parent_id?: string
        location_type?: string
        max_weight?: number
        max_volume?: number
        max_pallets?: number
      }
      Relationships: [
        {
          foreignKeyName: "warehouse_locations_parent_id_fkey",
          columns: ["tenant_id", "parent_id"],
          isOneToOne: false,
          referencedRelation: "warehouse_locations",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "warehouse_locations_warehouse_id_fkey",
          columns: ["tenant_id", "warehouse_id"],
          isOneToOne: false,
          referencedRelation: "warehouses",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    warehouse_users: {
      Row: {
        id: string
        tenant_id: string
        warehouse_id: string
        user_email: string
        role: string | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        warehouse_id: string
        user_email: string
        role?: string
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        warehouse_id?: string
        user_email?: string
        role?: string
        active?: boolean
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "warehouse_users_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
        {
          foreignKeyName: "warehouse_users_warehouse_id_fkey",
          columns: ["tenant_id", "warehouse_id"],
          isOneToOne: false,
          referencedRelation: "warehouses",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
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
      Insert: {
        id?: string
        code: string
        name: string
        address?: string
        city?: string
        postal_code?: string
        country?: string
        active?: boolean
        created_at?: string
        tenant_id: string
      }
      Update: {
        id?: string
        code?: string
        name?: string
        address?: string
        city?: string
        postal_code?: string
        country?: string
        active?: boolean
        created_at?: string
        tenant_id?: string
      }
      Relationships: [
        {
          foreignKeyName: "warehouses_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    webhook_delivery_logs: {
      Row: {
        id: string
        tenant_id: string
        endpoint_id: string | null
        url: string
        event: string
        status: string
        attempt: number | null
        response_code: number | null
        response_body: string | null
        error_message: string | null
        delivered_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        endpoint_id?: string
        url: string
        event: string
        status: string
        attempt?: number
        response_code?: number
        response_body?: string
        error_message?: string
        delivered_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        endpoint_id?: string
        url?: string
        event?: string
        status?: string
        attempt?: number
        response_code?: number
        response_body?: string
        error_message?: string
        delivered_at?: string
      }
      Relationships: [
      ]
    }
    webhook_delivery_queue: {
      Row: {
        id: string
        tenant_id: string
        endpoint_id: string
        event_name: string | null
        payload: Json
        signature: string | null
        attempts: number | null
        max_attempts: number | null
        next_attempt_at: string | null
        last_attempt_at: string | null
        last_response_status: number | null
        last_response_body: string | null
        status: string | null
        created_at: string | null
        url: string | null
        secret: string | null
        event: string | null
        last_error: string | null
        http_status: number | null
        response_body: string | null
        delivered_at: string | null
        updated_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        endpoint_id: string
        event_name?: string
        payload?: Json
        signature?: string
        attempts?: number
        max_attempts?: number
        next_attempt_at?: string
        last_attempt_at?: string
        last_response_status?: number
        last_response_body?: string
        status?: string
        created_at?: string
        url?: string
        secret?: string
        event?: string
        last_error?: string
        http_status?: number
        response_body?: string
        delivered_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        endpoint_id?: string
        event_name?: string
        payload?: Json
        signature?: string
        attempts?: number
        max_attempts?: number
        next_attempt_at?: string
        last_attempt_at?: string
        last_response_status?: number
        last_response_body?: string
        status?: string
        created_at?: string
        url?: string
        secret?: string
        event?: string
        last_error?: string
        http_status?: number
        response_body?: string
        delivered_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "webhook_delivery_queue_endpoint_id_fkey",
          columns: ["tenant_id", "endpoint_id"],
          isOneToOne: false,
          referencedRelation: "webhook_endpoints",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    webhook_endpoints: {
      Row: {
        id: string
        tenant_id: string
        name: string
        url: string
        secret: string | null
        active_events: Json | null
        active: boolean | null
        created_at: string
        updated_at: string
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        url: string
        secret?: string
        active_events?: Json
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        url?: string
        secret?: string
        active_events?: Json
        active?: boolean
        created_at?: string
        updated_at?: string
      }
      Relationships: [
      ]
    }
    webhook_event_catalog: {
      Row: {
        id: string
        event_name: string
        description: string
        payload_schema: Json | null
        category: string | null
        is_active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        event_name: string
        description: string
        payload_schema?: Json
        category?: string
        is_active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        event_name?: string
        description?: string
        payload_schema?: Json
        category?: string
        is_active?: boolean
        created_at?: string
      }
      Relationships: [
      ]
    }
    work_center_calendars: {
      Row: {
        id: string
        tenant_id: string
        work_center_id: string
        date: string
        available_hours: number | null
        is_holiday: boolean | null
        is_closed: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        work_center_id: string
        date: string
        available_hours?: number
        is_holiday?: boolean
        is_closed?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        work_center_id?: string
        date?: string
        available_hours?: number
        is_holiday?: boolean
        is_closed?: boolean
        created_at?: string
      }
      Relationships: [
      ]
    }
    work_centers: {
      Row: {
        id: string
        tenant_id: string
        code: string
        name: string
        capacity_hours_per_day: number | null
        cost_per_hour: number | null
        active: boolean | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        code: string
        name: string
        capacity_hours_per_day?: number
        cost_per_hour?: number
        active?: boolean
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        code?: string
        name?: string
        capacity_hours_per_day?: number
        cost_per_hour?: number
        active?: boolean
        created_at?: string
      }
      Relationships: [
      ]
    }
    work_hardship: {
      Row: {
        id: string
        tenant_id: string
        employee_id: string
        exposure_type: string
        exposure_level: string | null
        start_date: string | null
        end_date: string | null
        points: number | null
        notes: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        exposure_type: string
        exposure_level?: string
        start_date?: string
        end_date?: string
        points?: number
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        exposure_type?: string
        exposure_level?: string
        start_date?: string
        end_date?: string
        points?: number
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "work_hardship_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
      ]
    }
    work_hardship_records: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        exposure_type: string
        exposure_level: string
        exposure_start?: string
        exposure_end?: string
        duration_months?: number
        points?: number
        declaration_status?: string
        declared_at?: string
        notes?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        exposure_type?: string
        exposure_level?: string
        exposure_start?: string
        exposure_end?: string
        duration_months?: number
        points?: number
        declaration_status?: string
        declared_at?: string
        notes?: string
        created_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "work_hardship_records_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "work_hardship_records_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    work_stoppages: {
      Row: {
        id: string
        tenant_id: string
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
      Insert: {
        id?: string
        tenant_id: string
        employee_id: string
        stoppage_type: string
        start_date: string
        end_date?: string
        expected_end_date?: string
        reprise_date?: string
        reprise_type?: string
        days_count?: number
        working_days_count?: number
        subrogation?: boolean
        net_guarantee?: boolean
        ijss_net_amount?: number
        ijss_brut_amount?: number
        ijss_daily_rate?: number
        ijss_days_count?: number
        ijss_care_days?: number
        pas_days_count?: number
        employer_maintenance_amount?: number
        employer_maintenance_rate?: number
        bpij_number?: string
        bpij_imported_at?: string
        regularization_amount?: number
        regularization_type?: string
        medical_certificate_url?: string
        notes?: string
        status?: string
        created_at?: string
        updated_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        employee_id?: string
        stoppage_type?: string
        start_date?: string
        end_date?: string
        expected_end_date?: string
        reprise_date?: string
        reprise_type?: string
        days_count?: number
        working_days_count?: number
        subrogation?: boolean
        net_guarantee?: boolean
        ijss_net_amount?: number
        ijss_brut_amount?: number
        ijss_daily_rate?: number
        ijss_days_count?: number
        ijss_care_days?: number
        pas_days_count?: number
        employer_maintenance_amount?: number
        employer_maintenance_rate?: number
        bpij_number?: string
        bpij_imported_at?: string
        regularization_amount?: number
        regularization_type?: string
        medical_certificate_url?: string
        notes?: string
        status?: string
        created_at?: string
        updated_at?: string
      }
      Relationships: [
        {
          foreignKeyName: "work_stoppages_employee_id_fkey",
          columns: ["tenant_id", "employee_id"],
          isOneToOne: false,
          referencedRelation: "employees",
          referencedColumns: ["tenant_id", "id"]
        },
        {
          foreignKeyName: "work_stoppages_tenant_id_fkey",
          columns: ["tenant_id"],
          isOneToOne: true,
          referencedRelation: "tenants",
          referencedColumns: ["id"]
        },
      ]
    }
    workflows: {
      Row: {
        id: string
        tenant_id: string
        name: string
        description: string | null
        workflow_type: string | null
        schedule: string | null
        last_run: string | null
        status: string | null
        created_at: string | null
      }
      Insert: {
        id?: string
        tenant_id: string
        name: string
        description?: string
        workflow_type?: string
        schedule?: string
        last_run?: string
        status?: string
        created_at?: string
      }
      Update: {
        id?: string
        tenant_id?: string
        name?: string
        description?: string
        workflow_type?: string
        schedule?: string
        last_run?: string
        status?: string
        created_at?: string
      }
      Relationships: [
      ]
    }
    }
    Views: Record<string, never>
    Functions: Record<string, never>
    Enums: Record<string, never>
    CompositeTypes: Record<string, never>
  }
}
