export interface ProductCardDraft {
  name: string;
  description: string;
  characteristics: Record<string, string>;
  categoryId?: string;
  subcategoryId?: string;
  brandId?: string;
}

export interface ProductCardSource {
  text?: string;
  imageUrls?: readonly string[];
  barcode?: string;
}

/// Optional enrichment adapter. Implementations may use a rules engine,
/// supplier feed or contracted AI provider without coupling product CRUD.
export interface ProductCardGenerator {
  readonly id: string;
  generate(source: ProductCardSource): Promise<ProductCardDraft>;
}
