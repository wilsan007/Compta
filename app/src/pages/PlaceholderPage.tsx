import { Card, PageHeader, Button } from '@/components/ui'
import { Construction, ArrowLeft } from 'lucide-react'
import { useNavigate } from 'react-router-dom'

export function PlaceholderPage({ title, description }: { title: string; description?: string }) {
  const navigate = useNavigate()
  return (
    <div>
      <PageHeader title={title} subtitle={description} />
      <Card>
        <div className="flex flex-col items-center justify-center py-16">
          <div className="w-16 h-16 rounded-full bg-[var(--color-warning)] bg-opacity-10 flex items-center justify-center mb-4">
            <Construction className="w-8 h-8 text-[var(--color-warning)]" />
          </div>
          <h3 className="text-lg font-semibold text-[var(--color-text)] mb-2">En cours de développement</h3>
          <p className="text-sm text-[var(--color-text-secondary)] text-center max-w-md mb-6">
            Cette section est inspirée de Sage Accounting et sera implémentée dans une prochaine phase.
            Le squelette et la structure sont en place.
          </p>
          <Button variant="secondary" onClick={() => navigate(-1)}>
            <ArrowLeft className="w-4 h-4" /> Retour
          </Button>
        </div>
      </Card>
    </div>
  )
}
